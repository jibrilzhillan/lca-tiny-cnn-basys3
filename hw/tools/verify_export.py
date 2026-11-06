# verify_export.py
# Independently recompute integer Conv/Pool/FC and check every exported golden word.
import argparse
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tb/common'))
from cnn_test_config import architecture
from prepare_quant_params import parse_quant_params

def load(path,count,bits,signed=False):
    values=[int(x,16) for x in path.read_text().split()]
    if len(values)!=count: raise ValueError(f'{path.name}: {len(values)} words, expected {count}')
    if any(v<0 or v>=1<<bits for v in values): raise ValueError('Word width mismatch: '+path.name)
    if signed: values=[v-(1<<bits) if v>=(1<<(bits-1)) else v for v in values]
    return values

def verify(mem):
    a=architecture(); q=parse_quant_params((mem/'quant_params.txt').read_text(encoding='utf-8-sig'))
    n=a['NUM_IMAGES']; pix=a['PIXELS']; fs=a['CW']*a['CH']; ps=a['PW']*a['PH']
    images=load(mem/'test_images.mem',n*pix,8)
    w=load(mem/'conv_weight.mem',36,8,True); b=load(mem/'conv_bias.mem',4,32,True)
    fw=load(mem/'fc_weight.mem',a['FC_W'],8,True); fb=load(mem/'fc_bias.mem',3,32,True)
    expected_conv=load(mem/'golden/conv_all.mem',n*a['FMAP'],8)
    expected_pool=load(mem/'golden/pool_all.mem',n*a['POOL'],8)
    expected_logits=load(mem/'golden/logits_all.mem',n*3,32,True)
    expected_class=load(mem/'golden/expected_class.mem',n,2)
    labels=load(mem/'test_labels.mem',n,2)
    if any(not -(1<<23)<=v<(1<<23) for v in b): raise ValueError('Conv bias does not fit loaded int24 accumulator')
    reads=[]
    for c in range(4):
        for y in range(a['CH']):
            for x in range(a['CW']):
                reads += [(y+ky)*a['IMG_WIDTH']+x+kx for ky in range(3) for kx in range(3)]
    for image in range(n):
        conv=[]
        for c in range(4):
            for y in range(a['CH']):
                for x in range(a['CW']):
                    acc=b[c]
                    for k in range(9):
                        ky,kx=divmod(k,3)
                        acc+=images[image*pix+(y+ky)*a['IMG_WIDTH']+x+kx]*w[c*9+k]
                        if not -(1<<23)<=acc<(1<<23): raise ValueError('Conv accumulation overflow')
                    value=(acc+(1<<(q['S1']-1)))>>q['S1'] if q['S1'] else acc
                    conv.append(min(127,max(0,value)))
        pool=[]
        for c in range(4):
            for y in range(a['PH']):
                for x in range(a['PW']):
                    base=c*fs+2*y*a['CW']+2*x
                    pool.append(max(conv[base+d] for d in (0,1,a['CW'],a['CW']+1)))
        logits=[fb[c]+sum(pool[i]*fw[c*a['POOL']+i] for i in range(a['POOL'])) for c in range(3)]
        if any(not -(1<<31)<=v<(1<<31) for v in logits): raise ValueError('FC overflow')
        cls=max(range(3),key=lambda c:logits[c])
        for label,actual,expected in [('Conv',conv,expected_conv[image*a['FMAP']:(image+1)*a['FMAP']]),('Pool',pool,expected_pool[image*a['POOL']:(image+1)*a['POOL']]),('logits',logits,expected_logits[image*3:image*3+3])]:
            if actual!=expected:
                i=next(i for i,(x,y) in enumerate(zip(actual,expected)) if x!=y)
                raise ValueError(f'{label} mismatch image={image} index={i}: actual={actual[i]} expected={expected[i]}')
        if cls!=expected_class[image]: raise ValueError('Class mismatch')
    print(f'EXPORT CHECK PASSED: {n} images, every Conv/Pool/logit/class; correct vs labels {sum(x==y for x,y in zip(expected_class,labels))}/{n}')
    return reads

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mem-dir',type=Path,required=True);p.add_argument('--addresses',type=Path)
    args=p.parse_args()
    try:
        reads=verify(args.mem_dir)
        if args.addresses: args.addresses.write_text(''.join(f'{v:04X}\n' for v in reads),encoding='ascii')
    except (OSError,ValueError) as error:p.exit(1,f'EXPORT CHECK FAILED: {error}\n')

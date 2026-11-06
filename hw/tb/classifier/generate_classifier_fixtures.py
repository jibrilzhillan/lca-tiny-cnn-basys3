# generate_classifier_fixtures.py
# Verification fixtures for the classifier engines.
# Deterministic directed references; not trained weights or model exports.
from pathlib import Path
import argparse
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"common"))
from cnn_test_config import architecture, pixels as make_pixels

def generate(out):
    cfg=architecture()
    out.mkdir(parents=True, exist_ok=True)
    def write(name, data, digits):
        mask=(1 << (digits*4))-1
        (out/name).write_text(''.join(f'{v & mask:0{digits}X}\n' for v in data), encoding='ascii')
    pool_inputs=[]; pool_expected=[]
    for case in range(7):
        a=[(i*37+i//cfg["CW"]*11+case*23)%128 for i in range(cfg["FMAP"])]
        if case==0: a=[0]*cfg["FMAP"]
        if case==1: a=[127]*cfg["FMAP"]
        if 2<=case<=5:
            # Every window has a unique winning corner; rotate over cases.
            a=[0]*cfg["FMAP"]
            for c in range(cfg["CONV_FILTERS"]):
                for y in range(cfg["PH"]):
                    for x in range(cfg["PW"]):
                        addresses=[c*cfg["CW"]*cfg["CH"]+y*2*cfg["CW"]+x*2+d for d in (0,1,cfg["CW"],cfg["CW"]+1)]
                        winner=(c+y+x+case)%4
                        for tap,address in enumerate(addresses):
                            a[address]=127 if tap==winner else (address+case)%100
        pool_inputs+=a
        for c in range(cfg["CONV_FILTERS"]):
            for y in range(cfg["PH"]):
                for x in range(cfg["PW"]):
                    base=c*cfg["CW"]*cfg["CH"]+y*2*cfg["CW"]+x*2
                    pool_expected.append(max(a[base+d] for d in (0,1,cfg["CW"],cfg["CW"]+1)))
    write('classifier_pool_input.mem',pool_inputs,2)
    write('classifier_pool_expected.mem',pool_expected,2)
    weights=[((i*71+i//cfg["POOL"]*17)%256)-128 for i in range(cfg["FC_W"])]
    biases=[-1500000,700000,-220000]
    vectors=[[0]*cfg["POOL"],[127]*cfg["POOL"],[(i*43+7)%128 for i in range(cfg["POOL"])],
             [127 if i==0 else 0 for i in range(cfg["POOL"])],
             [127 if i==cfg["POOL"]-1 else 0 for i in range(cfg["POOL"])]]
    expected=[biases[j]+sum(a[i]*weights[j*cfg["POOL"]+i] for i in range(cfg["POOL"]))
              for a in vectors for j in range(3)]
    write('classifier_fc_w.mem',weights,2); write('classifier_fc_b.mem',biases,8)
    write('classifier_fc_input.mem',[v for a in vectors for v in a],2)
    write('classifier_fc_expected.mem',expected,8)
    write('fc_weight.mem',weights,2); write('fc_bias.mem',biases,8)
    images=[]; core_pool=[]; core_logits=[]
    for image in range(cfg["NUM_IMAGES"]):
        pixels=make_pixels(image,cfg)
        fmap=[(pixels[i%cfg["PIXELS"]]^i)&127 for i in range(cfg["FMAP"])]
        pooled=[]
        for c in range(cfg["CONV_FILTERS"]):
            for y in range(cfg["PH"]):
                for x in range(cfg["PW"]):
                    base=c*cfg["CW"]*cfg["CH"]+y*2*cfg["CW"]+x*2
                    pooled.append(max(fmap[base+d] for d in (0,1,cfg["CW"],cfg["CW"]+1)))
        images+=pixels; core_pool+=pooled
        core_logits += [biases[j]+sum(pooled[i]*weights[j*cfg["POOL"]+i] for i in range(cfg["POOL"])) for j in range(3)]
    write('classifier_core_images.mem',images,2)
    write('classifier_core_pool.mem',core_pool,2)
    write('classifier_core_logits.mem',core_logits,8)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,required=True)
    generate(parser.parse_args().output_dir)

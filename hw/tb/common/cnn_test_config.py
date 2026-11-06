# cnn_test_config.py
# Read test dimensions from the shared RTL header; no numerical training scales.
from pathlib import Path
import re

def architecture():
    text=(Path(__file__).resolve().parents[2]/'rtl/include/cnn_params.vh').read_text()
    def literal(name):
        match=re.search(r'^`define\s+CNN_'+name+r'\s+(\d+)\s*$',text,re.M)
        if not match: raise ValueError('Missing numeric architecture macro: '+name)
        return int(match[1])
    a={name:literal(name) for name in ['IMG_WIDTH','IMG_HEIGHT','NUM_IMAGES','CONV_FILTERS','CONV_KERNEL','POOL_SIZE','NUM_CLASSES']}
    assert a['CONV_KERNEL']==3 and a['POOL_SIZE']==2 and a['NUM_CLASSES']==3
    a['PIXELS']=a['IMG_WIDTH']*a['IMG_HEIGHT']
    a['CW']=a['IMG_WIDTH']-a['CONV_KERNEL']+1
    a['CH']=a['IMG_HEIGHT']-a['CONV_KERNEL']+1
    assert a['CW']%2==0 and a['CH']%2==0
    a['PW']=a['CW']//2; a['PH']=a['CH']//2
    a['FMAP']=a['CONV_FILTERS']*a['CW']*a['CH']
    a['POOL']=a['CONV_FILTERS']*a['PW']*a['PH']
    a['FC_W']=a['NUM_CLASSES']*a['POOL']
    return a

def pixels(image,a):
    # Distinguish high pixel-offset bits as well as all image selectors.
    return [(i*7 ^ (i//256)*37 ^ (image*13+29))&255 for i in range(a['PIXELS'])]

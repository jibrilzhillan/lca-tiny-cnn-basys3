# prepare_quant_params.py
# Validate the power-of-two scales and generate a build-local RTL header.
import argparse
import hashlib
from pathlib import Path
import re

REQUIRED=('Fw1','Fa','Fw2','S1')

def parse_quant_params(text):
    values={}
    for number,line in enumerate(text.splitlines(),1):
        stripped=line.strip()
        if not stripped or stripped.startswith(('#','//',';')): continue
        match=re.fullmatch(r'(Fw1|Fa|Fw2|S1)\s*(?:=|:|\s)\s*([+-]?\d+)\s*(?:(?:#|//|;).*|\(.*\))?',stripped)
        if not match:
            if re.match(r'(Fw1|Fa|Fw2|S1)\b',stripped):
                raise ValueError(f'Invalid scale declaration at line {number}')
            continue  # Human-readable explanatory lines are permitted.
        key,value=match.groups()
        if key in values: raise ValueError(f'Duplicate parameter: {key}')
        values[key]=int(value)
    missing=set(REQUIRED)-values.keys()
    if missing: raise ValueError('Missing parameters: '+', '.join(sorted(missing)))
    if any(not 0<=values[k]<=30 for k in REQUIRED):
        raise ValueError('Supported scale exponents and S1 are integers from 0 to 30')
    if values['S1']!=8+values['Fw1']-values['Fa']:
        raise ValueError('S1 must equal 8 + Fw1 - Fa for uint8 input')
    return values

def prepare(source,output):
    data=source.read_bytes()
    values=parse_quant_params(data.decode('utf-8-sig'))
    sha=hashlib.sha256(data).hexdigest()
    lines=['// cnn_quant_params.vh','// Generated from the model export (mem/quant_params.txt).',
           '// Build-local output; regenerate whenever quant_params.txt changes.',
           '`ifndef CNN_QUANT_PARAMS_VH','`define CNN_QUANT_PARAMS_VH',
           '`define CNN_QUANT_CONFIG_PRESENT 1']
    for key,macro in [('Fw1','CNN_FW1'),('Fa','CNN_FA'),('Fw2','CNN_FW2'),('S1','CNN_S1')]:
        lines.append(f'`define {macro} {values[key]}')
    lines += ['`define CNN_REQUANT_SHIFT `CNN_S1',
              '`define CNN_CONV_BIAS_FRAC (8 + `CNN_FW1)',
              '`define CNN_LOGIT_FRAC (`CNN_FA + `CNN_FW2)',
              f'`define CNN_QUANT_SOURCE_SHA256 "{sha}"','`endif','']
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text('\n'.join(lines),encoding='ascii')
    return values

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try: print('QUANT CONFIG:',prepare(args.input,args.output))
    except (OSError,ValueError) as error: parser.exit(1,f'QUANT ERROR: {error}\n')

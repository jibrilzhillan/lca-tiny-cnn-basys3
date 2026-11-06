# test_quant_params.py
# Reject missing/ambiguous/inconsistent export scales before HDL compilation.
from pathlib import Path
import sys
import tempfile
import os
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from prepare_quant_params import parse_quant_params,prepare

class QuantParamsTest(unittest.TestCase):
    def test_export_syntax_and_zero_shift(self):
        self.assertEqual(parse_quant_params('Fw1 = 7 # weights\nFa: 6\nFw2 8\nS1 = 9 (right shift)'),dict(Fw1=7,Fa=6,Fw2=8,S1=9))
        self.assertEqual(parse_quant_params('Fw1=0\nFa=8\nFw2=7\nS1=0')['S1'],0)
    def test_reject_bad_exports(self):
        valid='Fw1=7\nFa=6\nFw2=8\nS1=9'
        for text in [valid.replace('S1=9','S1=8'),valid+'\nFa=6',valid.replace('Fw2=8',''),valid.replace('Fw1=7','Fw1=seven'),valid.replace('Fa=6','Fa=-1')]:
            with self.subTest(text=text),self.assertRaises(ValueError): parse_quant_params(text)
    def test_no_stale_header_on_invalid_export(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("CNN_TEST_TMPDIR")) as directory:
            source=Path(directory)/'quant_params.txt'; dest=Path(directory)/'cnn_quant_params.vh'
            source.write_text('Fw1=7\nFa=6\nFw2=8\nS1=9')
            prepare(source,dest); previous=dest.read_bytes()
            self.assertIn(b'`define CNN_S1 9',previous)
            source.write_text('Fw1=7')
            with self.assertRaises(ValueError): prepare(source,dest)
            self.assertEqual(previous,dest.read_bytes())
            with self.assertRaises(FileNotFoundError): prepare(Path(directory)/'missing',dest)

if __name__=='__main__': unittest.main()

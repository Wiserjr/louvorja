"""python -m unittest ferramentas/test_texto_pdf.py (de dentro de biblia/)

Os casos ficam em test/dados/casos_normalizar.json e são os mesmos do teste
em Dart (test/trechos_test.dart): o app e o indexador precisam normalizar o
texto do PDF exatamente igual.
"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from texto_pdf import normalizar  # noqa: E402

CASOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "test",
                     "dados", "casos_normalizar.json")


class TestNormalizar(unittest.TestCase):
    def test_casos_compartilhados(self):
        with open(CASOS, encoding="utf-8") as f:
            casos = json.load(f)
        for caso in casos:
            with self.subTest(cru=caso["cru"]):
                self.assertEqual(normalizar(caso["cru"]), caso["esperado"])


if __name__ == "__main__":
    unittest.main()

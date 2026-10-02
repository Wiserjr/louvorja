"""python -m unittest ferramentas/test_referencias_pt.py (de dentro de biblia/)"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from referencias_pt import encontrar, formatar  # noqa: E402


def refs(texto, **kw):
    return [r.tupla() for r in encontrar(texto, **kw)]


class TestReferencias(unittest.TestCase):
    def test_simples(self):
        self.assertEqual(refs("disse Jesus”. Mateus 4:4."), [(40, 4004, 4004)])

    def test_intervalo(self):
        self.assertEqual(refs("Mateus 4:2-4"), [(40, 4002, 4004)])

    def test_lista_de_versiculos_vira_intervalo(self):
        self.assertEqual(refs("Apocalipse 3:7, 8."), [(66, 3007, 3008)])

    def test_lista_nao_contigua(self):
        self.assertEqual(refs("Mateus 4:4, 7, 10"),
                         [(40, 4004, 4004), (40, 4007, 4007), (40, 4010, 4010)])

    def test_varios_livros(self):
        texto = "Este capítulo é baseado em Mateus 4:1-11; Marcos 1:12, 13; " \
                "Lucas\r\n4:1-13."
        self.assertEqual(refs(texto), [
            (40, 4001, 4011), (41, 1012, 1013), (42, 4001, 4013)])

    def test_capitulos_inteiros(self):
        self.assertEqual(refs("baseado em Gênesis 1; 2."),
                         [(1, 1000, 2999)])

    def test_entre_capitulos(self):
        self.assertEqual(refs("Gênesis 4:25-6:2."), [(1, 4025, 6002)])

    def test_continuacao_de_capitulo(self):
        self.assertEqual(refs("Mateus 5:3; 6:9"),
                         [(40, 5003, 5003), (40, 6009, 6009)])

    def test_numerados(self):
        self.assertEqual(refs("1 João 3:2"), [(62, 3002, 3002)])
        self.assertEqual(refs("I Coríntios 13:4"), [(46, 13004, 13004)])
        self.assertEqual(refs("1Co 13:4"), [(46, 13004, 13004)])
        self.assertEqual(refs("2 Timóteo 3:16"), [(55, 3016, 3016)])

    def test_joao_e_jo(self):
        self.assertEqual(refs("João 3:16"), [(43, 3016, 3016)])
        self.assertEqual(refs("Jó 19:25"), [(18, 19025, 19025)])
        self.assertEqual(refs("Jo 3:16"), [(43, 3016, 3016)])

    def test_abreviacao_ambigua_exige_dois_pontos(self):
        self.assertEqual(refs("Os 12 apóstolos"), [])
        self.assertEqual(refs("Na 2 vez"), [])
        self.assertEqual(refs("Os 6:6"), [(28, 6006, 6006)])

    def test_capitulo_inteiro_por_extenso(self):
        self.assertEqual(refs("leia Salmo 23 todos os dias"),
                         [(19, 23000, 23999)])
        self.assertEqual(refs("Salmo 23", capitulos_inteiros=False), [])

    def test_livro_de_um_capitulo(self):
        self.assertEqual(refs("Judas 3"), [(65, 1003, 1003)])

    def test_capitulo_inexistente(self):
        self.assertEqual(refs("Atos 45:3"), [])
        self.assertEqual(refs("Mateus 4:0"), [])

    def test_outras_obras_nao_casam(self):
        self.assertEqual(refs("Testimonies for the Church 5:23"), [])
        self.assertEqual(refs("Mensagens Escolhidas 1:45"), [])

    def test_nao_casa_no_meio_da_palavra(self):
        self.assertEqual(refs("Joaquim 3:2"), [])

    def test_posicao(self):
        r = encontrar("Diz: “x”. Lucas 4:1. Fim")[0]
        self.assertEqual((r.inicio, r.final), (10, 19))

    def test_formatar(self):
        self.assertEqual(formatar(43, 3016, 3017), "João 3:16-17")
        self.assertEqual(formatar(19, 23000, 23999), "Salmos 23")
        self.assertEqual(formatar(1, 4025, 6002), "Gênesis 4:25-6:2")


if __name__ == "__main__":
    unittest.main()

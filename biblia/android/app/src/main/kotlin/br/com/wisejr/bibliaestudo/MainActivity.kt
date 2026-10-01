package br.com.wisejr.bibliaestudo

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    /** Resposta ao Dart que espera a volta da tela "Instalar apps desconhecidos". */
    private var aguardandoFonte: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Só na abertura de verdade, não numa recriação: aí o Dart pode estar no
        // meio de um download que isto apagaria.
        if (savedInstanceState == null) {
            Atualizador.limparCache(this)
            Atualizador.limparSessoes(this)
        }
    }

    // Consultado pelo InstalacaoReceiver: com o app em segundo plano, abrir a
    // confirmação é bloqueado em silêncio, e ele precisa notificar no lugar.
    override fun onResume() {
        super.onResume()
        VISIVEL.set(true)
    }

    override fun onPause() {
        VISIVEL.set(false)
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
            when (call.method) {
                "versaoInstalada" -> result.success(Atualizador.versaoInstalada(this))
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "precisaLiberarFonte" -> result.success(Atualizador.precisaLiberarFonte(this))
                "liberarFonte" -> liberarFonte(result)
                "conferirApk" -> result.success(Atualizador.conferir(this))
                "instalar" -> {
                    if (!Atualizador.arquivo(this).exists()) {
                        result.error("sem_arquivo", "A atualização não foi baixada.", null)
                    } else {
                        // Segue fora da thread principal: a cópia para a sessão e
                        // o fsync são síncronos e travariam a tela.
                        val app = applicationContext
                        Thread({ Atualizador.instalar(app) }, "instala-atualizacao").start()
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Abre a tela onde se libera a instalação e responde ao Dart na volta, com a
     * permissão reconsultada: aquela Activity não devolve resultado útil.
     */
    private fun liberarFonte(result: MethodChannel.Result) {
        if (aguardandoFonte != null) {
            result.error("ocupado", "Já há um pedido de permissão aberto.", null)
            return
        }
        aguardandoFonte = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(Atualizador.intentLiberarFonte(this), PEDIDO_FONTE)
        } catch (_: Exception) {
            aguardandoFonte = null
            result.success(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PEDIDO_FONTE) return
        val r = aguardandoFonte
        aguardandoFonte = null
        r?.success(!Atualizador.precisaLiberarFonte(this))
    }

    companion object {
        const val CANAL = "br.com.wisejr.bibliaestudo/atualizacao"
        private const val PEDIDO_FONTE = 4802
        private val VISIVEL = AtomicBoolean(false)

        fun emPrimeiroPlano(): Boolean = VISIVEL.get()
    }
}

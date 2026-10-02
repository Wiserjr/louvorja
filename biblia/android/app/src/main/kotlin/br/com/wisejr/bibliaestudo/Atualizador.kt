package br.com.wisejr.bibliaestudo

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Entrega ao instalador do sistema o APK que o lado Dart baixou
 * (lib/dados/atualizacao.dart), sem navegador e sem deixar arquivo em Downloads.
 *
 * É a mesma solução do app de recadastramento (Atualizador.java de lá), e as
 * exigências do Android que ela documenta valem aqui do mesmo jeito:
 *
 *  · O PendingIntent do commit() tem de ser MUTÁVEL. Com FLAG_IMMUTABLE o
 *    sistema descarta os extras que ele mesmo preenche, o receiver é acionado
 *    sem EXTRA_STATUS e a instalação não acontece — sem erro, sem diálogo.
 *  · Mutável com Intent implícito lança IllegalArgumentException em targetSdk
 *    34+. Por isso o receiver é declarado no manifesto e o Intent é explícito.
 *  · Todo stream do openWrite tem de estar FECHADO antes do commit, ou o commit
 *    lança SecurityException. fsync() vale só para o stream do openWrite.
 *  · setSize() com o tamanho real deixa o sistema pré-alocar o disco.
 *
 * instalar() recebe Context, não Activity, e roda numa thread de fundo: copiar
 * ~30 MB para a sessão e dar fsync na thread principal trava a tela.
 */
object Atualizador {

    /** Onde o Dart grava o download: getTemporaryDirectory() é o cacheDir. */
    const val ARQUIVO_CACHE = "atualizacao.apk"

    private val INSTALANDO = AtomicBoolean(false)

    /**
     * Do Android 8 em diante a permissão de instalar apps é POR APLICATIVO. Quem
     * instalou este app foi o navegador ou o gerenciador de arquivos, então é
     * ele que tem a permissão — na primeira autoatualização de todo aparelho,
     * este app ainda não tem.
     */
    fun precisaLiberarFonte(c: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !c.packageManager.canRequestPackageInstalls()

    fun intentLiberarFonte(c: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${c.packageName}"),
        )

    /** O versionCode instalado, como o Android o compara. */
    @Suppress("DEPRECATION")
    fun versaoInstalada(c: Context): Long =
        codigoDe(c.packageManager.getPackageInfo(c.packageName, 0))

    @Suppress("DEPRECATION")
    private fun codigoDe(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    /** O arquivo que o Dart baixa. Nenhum outro caminho é aceito. */
    fun arquivo(c: Context): File = File(c.cacheDir, ARQUIVO_CACHE)

    /**
     * Pacote e versão do APK baixado, ou null se ele não for um APK legível.
     *
     * Vale mais que conferir o tamanho: download truncado, página HTML no lugar
     * do binário ou lixo qualquer falham aqui, antes de envolver o instalador.
     */
    @Suppress("DEPRECATION")
    fun conferir(c: Context): Map<String, Any>? {
        val f = arquivo(c)
        if (!f.exists()) return null
        val info = c.packageManager.getPackageArchiveInfo(f.absolutePath, 0) ?: return null
        return mapOf("pacote" to info.packageName, "versionCode" to codigoDe(info))
    }

    /** Sobra de uma tentativa anterior. Chamado na abertura do app. */
    fun limparCache(c: Context) {
        if (INSTALANDO.get()) return
        try {
            File(c.cacheDir, ARQUIVO_CACHE).delete()
            File(c.cacheDir, "$ARQUIVO_CACHE.parcial").delete()
        } catch (_: Exception) {
            // cache: perder isto não afeta nada
        }
    }

    /**
     * Abandona sessões de instalação que ficaram para trás. Cada uma reserva o
     * tamanho do APK em disco, e o sistema só as recolhe sozinho depois de cerca
     * de um dia.
     */
    fun limparSessoes(c: Context) {
        try {
            val pi = c.packageManager.packageInstaller
            for (s in pi.mySessions) {
                try {
                    pi.abandonSession(s.sessionId)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
            // sem sessão a limpar
        }
    }

    /**
     * Entrega o APK ao instalador. Chamar de uma thread de fundo.
     *
     * A confirmação é do Android — o app não instala escondido. O resultado
     * chega ao InstalacaoReceiver.
     */
    fun instalar(c: Context) {
        if (!INSTALANDO.compareAndSet(false, true)) return
        val apk = arquivo(c)
        var sessao: PackageInstaller.Session? = null
        var id = -1
        try {
            val instalador = c.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            // Sem isto, um APK de outro pacote só falharia no fim.
            params.setAppPackageName(c.packageName)
            params.setSize(apk.length())

            id = instalador.createSession(params)
            sessao = instalador.openSession(id)

            FileInputStream(apk).use { entrada ->
                sessao.openWrite("app", 0, apk.length()).use { saida ->
                    entrada.copyTo(saida, 64 * 1024)
                    sessao.fsync(saida)
                }
            }

            // Explícito: exigido com FLAG_MUTABLE em targetSdk 34+.
            val aviso = Intent(c, InstalacaoReceiver::class.java)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
            val pi = PendingIntent.getBroadcast(c, id, aviso, flags)

            sessao.commit(pi.intentSender)
            sessao.close()
            sessao = null
        } catch (e: Exception) {
            if (sessao != null) {
                try { sessao.abandon() } catch (_: Exception) {}
                try { sessao.close() } catch (_: Exception) {}
            } else if (id > 0) {
                try { c.packageManager.packageInstaller.abandonSession(id) } catch (_: Exception) {}
            }
            INSTALANDO.set(false)
            limparCache(c)
            // Falta de espaço chega aqui também (openWrite/commit), não só pelo
            // STATUS_FAILURE_STORAGE do receiver.
            InstalacaoReceiver.avisar(c, "Não foi possível iniciar a instalação. " + Mensagens.NAO_DESINSTALE)
            return
        }
        INSTALANDO.set(false)
    }
}

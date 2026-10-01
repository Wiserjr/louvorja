package br.com.wisejr.bibliaestudo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/**
 * Recebe o resultado da instalação da atualização (ver Atualizador.kt).
 *
 * Declarado no manifesto, e não registrado em runtime: o commit() exige um
 * PendingIntent mutável, e mutável com Intent implícito lança exceção em
 * targetSdk 34+. Intent explícito exige um componente declarado.
 *
 * STATUS_PENDING_USER_ACTION é o passo NORMAL, não uma falha: o sistema pede
 * que abramos a tela de confirmação. Se o app estiver visível, abre direto. Se
 * não estiver — o download de ~30 MB leva minutos no 3G, e basta a tela apagar
 * ou entrar uma ligação —, do Android 10 em diante abrir uma Activity daqui é
 * bloqueado EM SILÊNCIO. A saída que a própria documentação indica é a
 * notificação que traz a pessoa de volta.
 */
class InstalacaoReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            // Pode chegar mais de uma vez; não abandonar a sessão.
            @Suppress("DEPRECATION")
            val confirmar = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
            if (MainActivity.emPrimeiroPlano()) {
                confirmar.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirmar)
                    return
                } catch (_: Exception) {
                    // cai na notificação abaixo
                }
            }
            notificarConfirmacao(context, confirmar)
            return
        }

        // Qualquer desfecho definitivo: o APK em cache não serve mais.
        Atualizador.limparCache(context)

        when (status) {
            // Na atualização do próprio app o processo costuma reiniciar antes
            // disto aparecer; o aviso é só a rede de segurança.
            PackageInstaller.STATUS_SUCCESS -> avisar(context, "Aplicativo atualizado.")
            // A pessoa cancelou no diálogo do sistema. Não é erro.
            PackageInstaller.STATUS_FAILURE_ABORTED -> {}
            // Quase sempre é chave de assinatura diferente: um APK de teste
            // compilado em outra máquina, por exemplo.
            PackageInstaller.STATUS_FAILURE_CONFLICT -> avisar(
                context,
                "A atualização foi assinada com outra chave e não entra por cima desta instalação.",
            )
            PackageInstaller.STATUS_FAILURE_INVALID -> avisar(
                context,
                "O arquivo da atualização chegou corrompido. Tente de novo.",
            )
            PackageInstaller.STATUS_FAILURE_STORAGE -> avisar(context, Mensagens.SEM_ESPACO)
            PackageInstaller.STATUS_FAILURE_BLOCKED -> avisar(
                context,
                "A instalação foi bloqueada pelo sistema do aparelho. " + Mensagens.NAO_DESINSTALE,
            )
            else -> avisar(context, "Não foi possível atualizar. " + Mensagens.NAO_DESINSTALE)
        }
    }

    private fun notificarConfirmacao(context: Context, confirmar: Intent) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
            // Declarar POST_NOTIFICATIONS não garante que ela foi concedida, e
            // notify() não lança quando não aparece — a pessoa ficaria esperando
            // uma confirmação que nunca vem.
            if (nm == null || !nm.areNotificationsEnabled()) {
                avisar(context, "Abra o aplicativo para concluir a atualização.")
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(CANAL, "Atualização do aplicativo", NotificationManager.IMPORTANCE_HIGH),
                )
            }
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_IMMUTABLE
            confirmar.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val toque = PendingIntent.getActivity(context, 0, confirmar, flags)

            @Suppress("DEPRECATION")
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CANAL)
            } else {
                Notification.Builder(context)
            }
            val n = b.setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("Atualização pronta para instalar")
                .setContentText("Toque para confirmar a instalação.")
                .setAutoCancel(true)
                .setContentIntent(toque)
                .build()
            nm.notify(ID_NOTIFICACAO, n)
        } catch (_: Exception) {
            avisar(context, "Abra o aplicativo para concluir a atualização.")
        }
    }

    companion object {
        private const val CANAL = "atualizacao"
        private const val ID_NOTIFICACAO = 4801

        fun avisar(c: Context, texto: String) {
            val app = c.applicationContext
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(app, texto, Toast.LENGTH_LONG).show()
            }
        }
    }
}

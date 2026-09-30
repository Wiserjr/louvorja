package br.com.wisejr.louvorja

/**
 * Textos que a pessoa lê quando a atualização falha.
 *
 * Num lugar só pelo mesmo motivo do app de recadastramento: toda falha deve
 * nomear a ação segura e desaconselhar a destrutiva. Aqui, desinstalar apaga as
 * músicas que o app baixou e os ajustes (pasta das músicas, voz da leitura,
 * hinário escolhido) — e "desinstalar e instalar de novo" é justamente o que
 * qualquer um tenta primeiro quando uma atualização não entra.
 *
 * Os toasts do Android 12+ mostram só duas linhas; por isso textos curtos.
 */
object Mensagens {

    const val NAO_DESINSTALE =
        "Não desinstale: as músicas baixadas pelo app seriam apagadas."

    const val SEM_ESPACO =
        "Sem espaço no aparelho para atualizar. Libere espaço e tente de novo."
}

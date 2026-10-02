package br.com.wisejr.bibliaestudo

/**
 * Textos que a pessoa lê quando a atualização falha.
 *
 * Num lugar só pelo mesmo motivo do app de recadastramento: toda falha deve
 * nomear a ação segura e desaconselhar a destrutiva. Aqui, desinstalar apaga os livros
 * de Ellen G. White e dos pioneiros que o app baixou, as marcações e os ajustes — e "desinstalar e instalar de novo" é justamente o que
 * qualquer um tenta primeiro quando uma atualização não entra.
 *
 * Os toasts do Android 12+ mostram só duas linhas; por isso textos curtos.
 */
object Mensagens {

    const val NAO_DESINSTALE =
        "Não desinstale: os livros baixados e as marcações seriam apagados."

    const val SEM_ESPACO =
        "Sem espaço no aparelho para atualizar. Libere espaço e tente de novo."
}

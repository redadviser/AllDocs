// Texts of the page a document request link opens, in the app's languages.

export type Lang = 'pt' | 'en' | 'es' | 'fr'

export function pickLang(value: unknown): Lang {
  const code = String(value ?? '').slice(0, 2).toLowerCase()
  return code === 'en' || code === 'es' || code === 'fr' ? code : 'pt'
}

type Texts = {
  asking: string
  until: string
  accepted: string
  choose: string
  send: string
  sending: string
  privacy: string
  doneTitle: string
  doneBody: string
  sendMore: string
  invalidTitle: string
  invalidBody: string
  tooBig: string
  badType: string
  tooMany: string
  failed: string
}

export const texts: Record<Lang, Texts> = {
  pt: {
    asking: '{name} pede-te um documento',
    until: 'Podes enviar até {date}.',
    accepted: 'PDF, fotos ou documentos do Office, até 25 MB cada.',
    choose: 'Escolher ficheiros',
    send: 'Enviar',
    sending: 'A enviar…',
    privacy: 'Os ficheiros ficam guardados encriptados e são apagados do servidor assim que chegam à app de {name}.',
    doneTitle: 'Enviado',
    doneBody: '{name} vai receber os ficheiros na app AllDocs. Podes fechar esta página.',
    sendMore: 'Enviar mais',
    invalidTitle: 'Este pedido já não está disponível',
    invalidBody: 'O link expirou ou o pedido foi fechado. Pede um link novo a quem to enviou.',
    tooBig: '{file} tem mais de 25 MB.',
    badType: '{file}: só são aceites PDF, fotos e documentos do Office.',
    tooMany: 'Este pedido já recebeu o máximo de ficheiros.',
    failed: 'Não foi possível enviar. Verifica a ligação e tenta novamente.',
  },
  en: {
    asking: '{name} is asking you for a document',
    until: 'You can send it until {date}.',
    accepted: 'PDF, photos or Office documents, up to 25 MB each.',
    choose: 'Choose files',
    send: 'Send',
    sending: 'Sending…',
    privacy: "Files are stored encrypted and deleted from the server as soon as they reach {name}'s app.",
    doneTitle: 'Sent',
    doneBody: '{name} will get the files in the AllDocs app. You can close this page.',
    sendMore: 'Send more',
    invalidTitle: 'This request is no longer available',
    invalidBody: 'The link has expired or the request was closed. Ask whoever sent it for a new link.',
    tooBig: '{file} is larger than 25 MB.',
    badType: '{file}: only PDFs, photos and Office documents are accepted.',
    tooMany: 'This request has already received the maximum number of files.',
    failed: "That didn't send. Check your connection and try again.",
  },
  es: {
    asking: '{name} te pide un documento',
    until: 'Puedes enviarlo hasta el {date}.',
    accepted: 'PDF, fotos o documentos de Office, hasta 25 MB cada uno.',
    choose: 'Elegir archivos',
    send: 'Enviar',
    sending: 'Enviando…',
    privacy: 'Los archivos se guardan cifrados y se borran del servidor en cuanto llegan a la app de {name}.',
    doneTitle: 'Enviado',
    doneBody: '{name} recibirá los archivos en la app AllDocs. Puedes cerrar esta página.',
    sendMore: 'Enviar más',
    invalidTitle: 'Esta solicitud ya no está disponible',
    invalidBody: 'El enlace ha caducado o la solicitud se cerró. Pide un enlace nuevo a quien te lo envió.',
    tooBig: '{file} ocupa más de 25 MB.',
    badType: '{file}: solo se aceptan PDF, fotos y documentos de Office.',
    tooMany: 'Esta solicitud ya ha recibido el máximo de archivos.',
    failed: 'No se pudo enviar. Comprueba la conexión e inténtalo de nuevo.',
  },
  fr: {
    asking: '{name} vous demande un document',
    until: "Vous pouvez l'envoyer jusqu'au {date}.",
    accepted: "PDF, photos ou documents Office, jusqu'à 25 Mo chacun.",
    choose: 'Choisir des fichiers',
    send: 'Envoyer',
    sending: 'Envoi…',
    privacy: "Les fichiers sont stockés chiffrés et supprimés du serveur dès qu'ils arrivent dans l'app de {name}.",
    doneTitle: 'Envoyé',
    doneBody: '{name} recevra les fichiers dans l’app AllDocs. Vous pouvez fermer cette page.',
    sendMore: 'Envoyer d’autres fichiers',
    invalidTitle: "Cette demande n'est plus disponible",
    invalidBody: 'Le lien a expiré ou la demande a été fermée. Demandez un nouveau lien à la personne qui vous l’a envoyé.',
    tooBig: '{file} dépasse 25 Mo.',
    badType: '{file} : seuls les PDF, photos et documents Office sont acceptés.',
    tooMany: 'Cette demande a déjà reçu le nombre maximal de fichiers.',
    failed: "L'envoi a échoué. Vérifiez la connexion et réessayez.",
  },
}

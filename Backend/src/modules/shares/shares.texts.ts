// Texts of the page a secure share link opens, in the app's languages.

import type { Lang } from '../requests/requests.texts'

type Texts = {
  sharedBy: string
  until: string
  viewsLeft: string
  viewLeft: string
  codeLabel: string
  codeHint: string
  open: string
  download: string
  wrongCode: string
  privacy: string
  invalidTitle: string
  invalidBody: string
  lockedTitle: string
  lockedBody: string
}

export const texts: Record<Lang, Texts> = {
  pt: {
    sharedBy: '{name} partilhou um documento contigo',
    until: 'Disponível até {date}',
    viewsLeft: 'Pode ser aberto mais {n} vezes',
    viewLeft: 'Só pode ser aberto mais uma vez',
    codeLabel: 'Código de acesso',
    codeHint: 'Pede o código a {name}.',
    open: 'Abrir',
    download: 'Descarregar',
    wrongCode: 'Código errado. Restam {n} tentativas.',
    privacy: 'Partilhado de forma segura com a AllDocs. O link deixa de funcionar quando expira ou quando {name} o revogar.',
    invalidTitle: 'Este link já não está disponível',
    invalidBody: 'Pode ter expirado ou sido revogado por quem o partilhou. Pede-lhe um link novo.',
    lockedTitle: 'Link bloqueado',
    lockedBody: 'Foram tentados códigos errados demasiadas vezes. Pede um link novo a quem o partilhou.',
  },
  en: {
    sharedBy: '{name} shared a document with you',
    until: 'Available until {date}',
    viewsLeft: 'Can be opened {n} more times',
    viewLeft: 'Can be opened only once more',
    codeLabel: 'Access code',
    codeHint: 'Ask {name} for the code.',
    open: 'Open',
    download: 'Download',
    wrongCode: 'Wrong code. {n} attempts left.',
    privacy: 'Shared securely with AllDocs. The link stops working when it expires or when {name} revokes it.',
    invalidTitle: 'This link is no longer available',
    invalidBody: 'It may have expired or been revoked by whoever shared it. Ask them for a new link.',
    lockedTitle: 'Link blocked',
    lockedBody: 'Wrong codes were tried too many times. Ask whoever shared it for a new link.',
  },
  es: {
    sharedBy: '{name} ha compartido un documento contigo',
    until: 'Disponible hasta el {date}',
    viewsLeft: 'Se puede abrir {n} veces más',
    viewLeft: 'Solo se puede abrir una vez más',
    codeLabel: 'Código de acceso',
    codeHint: 'Pide el código a {name}.',
    open: 'Abrir',
    download: 'Descargar',
    wrongCode: 'Código incorrecto. Quedan {n} intentos.',
    privacy: 'Compartido de forma segura con AllDocs. El enlace deja de funcionar cuando caduca o cuando {name} lo revoca.',
    invalidTitle: 'Este enlace ya no está disponible',
    invalidBody: 'Puede haber caducado o haber sido revocado por quien lo compartió. Pídele un enlace nuevo.',
    lockedTitle: 'Enlace bloqueado',
    lockedBody: 'Se han probado códigos incorrectos demasiadas veces. Pide un enlace nuevo a quien lo compartió.',
  },
  fr: {
    sharedBy: '{name} a partagé un document avec vous',
    until: 'Disponible jusqu’au {date}',
    viewsLeft: 'Peut encore être ouvert {n} fois',
    viewLeft: 'Ne peut plus être ouvert qu’une fois',
    codeLabel: 'Code d’accès',
    codeHint: 'Demandez le code à {name}.',
    open: 'Ouvrir',
    download: 'Télécharger',
    wrongCode: 'Code incorrect. Il reste {n} essais.',
    privacy: 'Partagé en toute sécurité avec AllDocs. Le lien cesse de fonctionner à son expiration ou quand {name} le révoque.',
    invalidTitle: 'Ce lien n’est plus disponible',
    invalidBody: 'Il a peut-être expiré ou été révoqué par la personne qui l’a partagé. Demandez-lui un nouveau lien.',
    lockedTitle: 'Lien bloqué',
    lockedBody: 'Trop de codes incorrects ont été essayés. Demandez un nouveau lien à la personne qui l’a partagé.',
  },
}

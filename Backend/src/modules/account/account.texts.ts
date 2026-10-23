// Account deletion: the confirmation email and the web pages, in the app's
// languages.

import type { Lang } from '../requests/requests.texts'

type Texts = {
  emailSubject: string
  emailBody: string
  emailButton: string
  emailIgnore: string
  askTitle: string
  askIntro: string
  emailLabel: string
  sendLink: string
  sentTitle: string
  sentBody: string
  confirmTitle: string
  confirmIntro: string
  deletedHeading: string
  deletedItems: string[]
  keptHeading: string
  keptItems: string[]
  subscriptionWarning: string
  manageGoogle: string
  manageApple: string
  checkbox: string
  deleteButton: string
  doneTitle: string
  doneBody: string
  invalidTitle: string
  invalidBody: string
  askAgain: string
}

export const texts: Record<Lang, Texts> = {
  pt: {
    emailSubject: 'Confirma a eliminação da tua conta AllDocs',
    emailBody: 'Pediste para eliminar a tua conta AllDocs ({email}). Abre o link para ver o que é apagado e confirmar. O link é válido durante uma hora.',
    emailButton: 'Rever e eliminar a conta',
    emailIgnore: 'Se não foste tu, ignora este email: a tua conta continua como está.',
    askTitle: 'Eliminar a conta AllDocs',
    askIntro: 'Escreve o email da tua conta. Enviamos-te um link para confirmares a eliminação.',
    emailLabel: 'Email da conta',
    sendLink: 'Enviar link de confirmação',
    sentTitle: 'Verifica o teu email',
    sentBody: 'Se existir uma conta AllDocs com esse email, enviámos-lhe um link para confirmar a eliminação. O link é válido durante uma hora.',
    confirmTitle: 'Eliminar a tua conta',
    confirmIntro: 'Conta {email}. Isto não pode ser desfeito.',
    deletedHeading: 'É apagado de vez',
    deletedItems: [
      'A tua conta, o teu perfil e as sessões em todos os aparelhos',
      'Os links seguros e os pedidos de documentos, com os ficheiros no servidor',
      'A sincronização entre aparelhos e tudo o que estava à espera no servidor',
    ],
    keptHeading: 'Não é apagado por nós',
    keptItems: [
      'Os documentos guardados nos teus telemóveis (ficam lá; podes apagá-los desinstalando a app)',
      'Os backups que fizeste na tua Google Drive ou Dropbox',
    ],
    subscriptionWarning: 'Tens uma subscrição Folio ou Vault? Eliminar a conta não a cancela. Cancela-a primeiro na loja:',
    manageGoogle: 'Google Play',
    manageApple: 'App Store',
    checkbox: 'Percebo que a minha conta é eliminada de vez e que isto não pode ser desfeito.',
    deleteButton: 'Eliminar a conta definitivamente',
    doneTitle: 'Conta eliminada',
    doneBody: 'A tua conta AllDocs e os dados no nosso servidor foram apagados. Obrigado por teres usado a AllDocs.',
    invalidTitle: 'Este link já não é válido',
    invalidBody: 'Pode ter expirado (dura uma hora) ou já ter sido usado. Pede um novo.',
    askAgain: 'Pedir um novo link',
  },
  en: {
    emailSubject: 'Confirm deleting your AllDocs account',
    emailBody: 'You asked to delete your AllDocs account ({email}). Open the link to see what is deleted and confirm. The link is valid for one hour.',
    emailButton: 'Review and delete the account',
    emailIgnore: "If this wasn't you, ignore this email: your account stays as it is.",
    askTitle: 'Delete your AllDocs account',
    askIntro: "Enter your account's email. We'll send you a link to confirm the deletion.",
    emailLabel: 'Account email',
    sendLink: 'Send confirmation link',
    sentTitle: 'Check your email',
    sentBody: 'If an AllDocs account exists for that email, we sent it a link to confirm the deletion. The link is valid for one hour.',
    confirmTitle: 'Delete your account',
    confirmIntro: 'Account {email}. This cannot be undone.',
    deletedHeading: 'Deleted for good',
    deletedItems: [
      'Your account, your profile and the sessions on every device',
      'Your secure links and document requests, with their files on the server',
      'Device sync and everything waiting on the server',
    ],
    keptHeading: 'Not deleted by us',
    keptItems: [
      'The documents stored on your phones (they stay there; uninstalling the app removes them)',
      'The backups you made to your Google Drive or Dropbox',
    ],
    subscriptionWarning: "Do you have a Folio or Vault subscription? Deleting the account doesn't cancel it. Cancel it first in the store:",
    manageGoogle: 'Google Play',
    manageApple: 'App Store',
    checkbox: 'I understand my account is deleted for good and this cannot be undone.',
    deleteButton: 'Delete the account permanently',
    doneTitle: 'Account deleted',
    doneBody: 'Your AllDocs account and its data on our server were deleted. Thank you for using AllDocs.',
    invalidTitle: 'This link is no longer valid',
    invalidBody: 'It may have expired (it lasts one hour) or been used already. Ask for a new one.',
    askAgain: 'Ask for a new link',
  },
  es: {
    emailSubject: 'Confirma la eliminación de tu cuenta AllDocs',
    emailBody: 'Has pedido eliminar tu cuenta AllDocs ({email}). Abre el enlace para ver qué se borra y confirmar. El enlace es válido durante una hora.',
    emailButton: 'Revisar y eliminar la cuenta',
    emailIgnore: 'Si no has sido tú, ignora este correo: tu cuenta sigue como está.',
    askTitle: 'Eliminar la cuenta AllDocs',
    askIntro: 'Escribe el correo de tu cuenta. Te enviaremos un enlace para confirmar la eliminación.',
    emailLabel: 'Correo de la cuenta',
    sendLink: 'Enviar enlace de confirmación',
    sentTitle: 'Revisa tu correo',
    sentBody: 'Si existe una cuenta AllDocs con ese correo, le hemos enviado un enlace para confirmar la eliminación. El enlace es válido durante una hora.',
    confirmTitle: 'Eliminar tu cuenta',
    confirmIntro: 'Cuenta {email}. Esto no se puede deshacer.',
    deletedHeading: 'Se borra definitivamente',
    deletedItems: [
      'Tu cuenta, tu perfil y las sesiones en todos los dispositivos',
      'Tus enlaces seguros y solicitudes de documentos, con sus archivos en el servidor',
      'La sincronización entre dispositivos y todo lo que esperaba en el servidor',
    ],
    keptHeading: 'No lo borramos nosotros',
    keptItems: [
      'Los documentos guardados en tus teléfonos (se quedan ahí; desinstalar la app los borra)',
      'Las copias que hiciste en tu Google Drive o Dropbox',
    ],
    subscriptionWarning: '¿Tienes una suscripción Folio o Vault? Eliminar la cuenta no la cancela. Cancélala primero en la tienda:',
    manageGoogle: 'Google Play',
    manageApple: 'App Store',
    checkbox: 'Entiendo que mi cuenta se elimina definitivamente y que esto no se puede deshacer.',
    deleteButton: 'Eliminar la cuenta definitivamente',
    doneTitle: 'Cuenta eliminada',
    doneBody: 'Tu cuenta AllDocs y sus datos en nuestro servidor se han borrado. Gracias por usar AllDocs.',
    invalidTitle: 'Este enlace ya no es válido',
    invalidBody: 'Puede haber caducado (dura una hora) o haberse usado ya. Pide uno nuevo.',
    askAgain: 'Pedir un enlace nuevo',
  },
  fr: {
    emailSubject: 'Confirmez la suppression de votre compte AllDocs',
    emailBody: 'Vous avez demandé à supprimer votre compte AllDocs ({email}). Ouvrez le lien pour voir ce qui est supprimé et confirmer. Le lien est valable une heure.',
    emailButton: 'Vérifier et supprimer le compte',
    emailIgnore: "Si ce n'était pas vous, ignorez cet e-mail : votre compte reste tel quel.",
    askTitle: 'Supprimer le compte AllDocs',
    askIntro: "Saisissez l'e-mail de votre compte. Nous vous enverrons un lien pour confirmer la suppression.",
    emailLabel: 'E-mail du compte',
    sendLink: 'Envoyer le lien de confirmation',
    sentTitle: 'Vérifiez vos e-mails',
    sentBody: 'Si un compte AllDocs existe pour cet e-mail, nous lui avons envoyé un lien pour confirmer la suppression. Le lien est valable une heure.',
    confirmTitle: 'Supprimer votre compte',
    confirmIntro: 'Compte {email}. Cette action est irréversible.',
    deletedHeading: 'Supprimé définitivement',
    deletedItems: [
      'Votre compte, votre profil et les sessions sur tous les appareils',
      'Vos liens sécurisés et demandes de documents, avec leurs fichiers sur le serveur',
      'La synchronisation entre appareils et tout ce qui attendait sur le serveur',
    ],
    keptHeading: 'Non supprimé par nous',
    keptItems: [
      "Les documents enregistrés sur vos téléphones (ils y restent ; désinstaller l'app les supprime)",
      'Les sauvegardes faites sur votre Google Drive ou Dropbox',
    ],
    subscriptionWarning: "Vous avez un abonnement Folio ou Vault ? Supprimer le compte ne l'annule pas. Annulez-le d'abord dans la boutique :",
    manageGoogle: 'Google Play',
    manageApple: 'App Store',
    checkbox: "Je comprends que mon compte est supprimé définitivement et que c'est irréversible.",
    deleteButton: 'Supprimer le compte définitivement',
    doneTitle: 'Compte supprimé',
    doneBody: "Votre compte AllDocs et ses données sur notre serveur ont été supprimés. Merci d'avoir utilisé AllDocs.",
    invalidTitle: "Ce lien n'est plus valable",
    invalidBody: 'Il a peut-être expiré (il dure une heure) ou déjà été utilisé. Demandez-en un nouveau.',
    askAgain: 'Demander un nouveau lien',
  },
}

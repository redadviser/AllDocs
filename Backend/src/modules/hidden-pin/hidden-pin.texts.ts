// Emails and the cancel page of the hidden albums' PIN reset.

import type { Lang } from '../requests/requests.texts'

type Texts = {
  codeSubject: string
  codeBody: string
  codeNote: string
  warnSubject: string
  warnBody: string
  warnButton: string
  warnAdvice: string
  cancelledTitle: string
  cancelledBody: string
  invalidTitle: string
  invalidBody: string
}

export const texts: Record<Lang, Texts> = {
  pt: {
    codeSubject: 'Código para repor o PIN dos álbuns ocultos',
    codeBody: 'Pediste para repor o PIN dos teus álbuns ocultos na AllDocs. O teu código é:',
    codeNote: 'Expira em {minutes} minutos. Depois de o confirmares, por segurança o PIN novo só pode ser criado ao fim de {hours} horas. Se não foste tu, ignora este email e muda a palavra-passe da conta.',
    warnSubject: 'Pedido para repor o PIN dos álbuns ocultos',
    warnBody: 'O código foi confirmado num aparelho com a tua conta. Daqui a {hours} horas vai poder ser criado um PIN novo para os teus álbuns ocultos. Se não foste tu, cancela o pedido agora:',
    warnButton: 'Cancelar o pedido',
    warnAdvice: 'Se não foste tu, recomendamos também que mudes a palavra-passe da conta e termines a sessão nos aparelhos que não reconheces (Perfil › Segurança).',
    cancelledTitle: 'Pedido cancelado',
    cancelledBody: 'O PIN dos álbuns ocultos não vai ser reposto. Os teus álbuns continuam protegidos pelo PIN de sempre.',
    invalidTitle: 'Este link já não está ativo',
    invalidBody: 'O pedido já foi cancelado ou concluído.',
  },
  en: {
    codeSubject: 'Code to reset your hidden albums PIN',
    codeBody: 'You asked to reset the PIN of your hidden albums in AllDocs. Your code is:',
    codeNote: 'It expires in {minutes} minutes. Once you confirm it, for your security the new PIN can only be set after {hours} hours. If this wasn\'t you, ignore this email and change your account password.',
    warnSubject: 'Request to reset your hidden albums PIN',
    warnBody: 'The code was confirmed on a device signed in to your account. In {hours} hours a new PIN can be set for your hidden albums. If this wasn\'t you, cancel the request now:',
    warnButton: 'Cancel the request',
    warnAdvice: 'If this wasn\'t you, we also recommend changing your account password and signing out devices you don\'t recognise (Profile › Security).',
    cancelledTitle: 'Request cancelled',
    cancelledBody: 'The hidden albums PIN won\'t be reset. Your albums are still protected by your usual PIN.',
    invalidTitle: 'This link is no longer active',
    invalidBody: 'The request was already cancelled or completed.',
  },
  es: {
    codeSubject: 'Código para restablecer el PIN de los álbumes ocultos',
    codeBody: 'Has pedido restablecer el PIN de tus álbumes ocultos en AllDocs. Tu código es:',
    codeNote: 'Caduca en {minutes} minutos. Una vez confirmado, por seguridad el PIN nuevo solo se podrá crear pasadas {hours} horas. Si no has sido tú, ignora este correo y cambia la contraseña de la cuenta.',
    warnSubject: 'Solicitud para restablecer el PIN de los álbumes ocultos',
    warnBody: 'El código se ha confirmado en un dispositivo con tu cuenta. Dentro de {hours} horas se podrá crear un PIN nuevo para tus álbumes ocultos. Si no has sido tú, cancela la solicitud ahora:',
    warnButton: 'Cancelar la solicitud',
    warnAdvice: 'Si no has sido tú, te recomendamos también cambiar la contraseña de la cuenta y cerrar la sesión en los dispositivos que no reconozcas (Perfil › Seguridad).',
    cancelledTitle: 'Solicitud cancelada',
    cancelledBody: 'El PIN de los álbumes ocultos no se restablecerá. Tus álbumes siguen protegidos por el PIN de siempre.',
    invalidTitle: 'Este enlace ya no está activo',
    invalidBody: 'La solicitud ya se canceló o se completó.',
  },
  fr: {
    codeSubject: 'Code pour réinitialiser le code PIN des albums masqués',
    codeBody: 'Vous avez demandé à réinitialiser le code PIN de vos albums masqués dans AllDocs. Votre code est :',
    codeNote: 'Il expire dans {minutes} minutes. Une fois confirmé, par sécurité le nouveau code PIN ne pourra être créé qu’après {hours} heures. Si ce n’était pas vous, ignorez cet e-mail et changez le mot de passe du compte.',
    warnSubject: 'Demande de réinitialisation du code PIN des albums masqués',
    warnBody: 'Le code a été confirmé sur un appareil connecté à votre compte. Dans {hours} heures, un nouveau code PIN pourra être créé pour vos albums masqués. Si ce n’était pas vous, annulez la demande maintenant :',
    warnButton: 'Annuler la demande',
    warnAdvice: 'Si ce n’était pas vous, nous vous recommandons aussi de changer le mot de passe du compte et de déconnecter les appareils que vous ne reconnaissez pas (Profil › Sécurité).',
    cancelledTitle: 'Demande annulée',
    cancelledBody: 'Le code PIN des albums masqués ne sera pas réinitialisé. Vos albums restent protégés par votre code habituel.',
    invalidTitle: 'Ce lien n’est plus actif',
    invalidBody: 'La demande a déjà été annulée ou terminée.',
  },
}

// Texts of the password reset email and page, in the app's languages.

export type Lang = 'pt' | 'en' | 'es' | 'fr'

export function pickLang(value: unknown): Lang {
  const code = String(value ?? '').slice(0, 2).toLowerCase()
  return code === 'en' || code === 'es' || code === 'fr' ? code : 'pt'
}

// Reads the browser's Accept-Language when the link carries no ?lang=.
export function langFromHeader(header: string | undefined): Lang {
  for (const part of (header ?? '').split(',')) {
    const code = part.trim().slice(0, 2).toLowerCase()
    if (code === 'pt' || code === 'en' || code === 'es' || code === 'fr') return code
  }
  return 'pt'
}

export const texts: Record<
  Lang,
  {
    emailSubject: string
    emailGreeting: string
    emailBody: string
    emailButton: string
    emailIgnore: string
    pageTitle: string
    pageIntro: string
    newPassword: string
    confirmPassword: string
    save: string
    tooShort: string
    mismatch: string
    invalidTitle: string
    invalidBody: string
    doneTitle: string
    doneBody: string
    failed: string
  }
> = {
  pt: {
    emailSubject: 'Redefinir a tua password da AllDocs',
    emailGreeting: 'Olá,',
    emailBody:
      'Recebemos um pedido para redefinir a password da tua conta AllDocs. Toca no botão para escolheres uma nova. O link é válido durante 1 hora e só pode ser usado uma vez.',
    emailButton: 'Definir nova password',
    emailIgnore: 'Se não foste tu a pedir, ignora este email — a tua password continua a mesma.',
    pageTitle: 'Nova password',
    pageIntro: 'Escolhe uma nova password para a tua conta AllDocs.',
    newPassword: 'Nova password',
    confirmPassword: 'Confirmar password',
    save: 'Guardar password',
    tooShort: 'A password tem de ter pelo menos 6 caracteres.',
    mismatch: 'As passwords não coincidem.',
    invalidTitle: 'Link inválido ou expirado',
    invalidBody: 'Este link já foi usado ou passou mais de 1 hora. Pede um novo na app, em "Esqueci-me".',
    doneTitle: 'Password alterada',
    doneBody: 'Já podes entrar na app AllDocs com a nova password. Por segurança, terminámos as sessões abertas noutros dispositivos.',
    failed: 'Não foi possível guardar. Tenta novamente.',
  },
  en: {
    emailSubject: 'Reset your AllDocs password',
    emailGreeting: 'Hi,',
    emailBody:
      'We received a request to reset the password of your AllDocs account. Tap the button to choose a new one. The link is valid for 1 hour and can only be used once.',
    emailButton: 'Set a new password',
    emailIgnore: "If you didn't ask for this, ignore this email — your password stays the same.",
    pageTitle: 'New password',
    pageIntro: 'Choose a new password for your AllDocs account.',
    newPassword: 'New password',
    confirmPassword: 'Confirm password',
    save: 'Save password',
    tooShort: 'The password must be at least 6 characters.',
    mismatch: "The passwords don't match.",
    invalidTitle: 'Invalid or expired link',
    invalidBody: 'This link was already used or is more than 1 hour old. Ask for a new one in the app, under "Forgot".',
    doneTitle: 'Password changed',
    doneBody: 'You can now sign in to the AllDocs app with your new password. For safety, sessions on other devices were ended.',
    failed: "Couldn't save it. Please try again.",
  },
  es: {
    emailSubject: 'Restablece tu contraseña de AllDocs',
    emailGreeting: 'Hola,',
    emailBody:
      'Hemos recibido una solicitud para restablecer la contraseña de tu cuenta de AllDocs. Toca el botón para elegir una nueva. El enlace es válido durante 1 hora y solo se puede usar una vez.',
    emailButton: 'Definir nueva contraseña',
    emailIgnore: 'Si no lo has pedido tú, ignora este email: tu contraseña sigue siendo la misma.',
    pageTitle: 'Nueva contraseña',
    pageIntro: 'Elige una nueva contraseña para tu cuenta de AllDocs.',
    newPassword: 'Nueva contraseña',
    confirmPassword: 'Confirmar contraseña',
    save: 'Guardar contraseña',
    tooShort: 'La contraseña debe tener al menos 6 caracteres.',
    mismatch: 'Las contraseñas no coinciden.',
    invalidTitle: 'Enlace no válido o caducado',
    invalidBody: 'Este enlace ya se ha usado o tiene más de 1 hora. Pide uno nuevo en la app, en "Olvidé".',
    doneTitle: 'Contraseña cambiada',
    doneBody: 'Ya puedes entrar en la app AllDocs con la nueva contraseña. Por seguridad, hemos cerrado las sesiones en otros dispositivos.',
    failed: 'No se ha podido guardar. Inténtalo de nuevo.',
  },
  fr: {
    emailSubject: 'Réinitialise ton mot de passe AllDocs',
    emailGreeting: 'Bonjour,',
    emailBody:
      "Nous avons reçu une demande de réinitialisation du mot de passe de ton compte AllDocs. Touche le bouton pour en choisir un nouveau. Le lien est valable 1 heure et ne peut être utilisé qu'une fois.",
    emailButton: 'Définir un nouveau mot de passe',
    emailIgnore: "Si tu n'es pas à l'origine de cette demande, ignore cet email — ton mot de passe reste le même.",
    pageTitle: 'Nouveau mot de passe',
    pageIntro: 'Choisis un nouveau mot de passe pour ton compte AllDocs.',
    newPassword: 'Nouveau mot de passe',
    confirmPassword: 'Confirmer le mot de passe',
    save: 'Enregistrer',
    tooShort: 'Le mot de passe doit contenir au moins 6 caractères.',
    mismatch: 'Les mots de passe ne correspondent pas.',
    invalidTitle: 'Lien invalide ou expiré',
    invalidBody: "Ce lien a déjà été utilisé ou date de plus d'1 heure. Demandes-en un nouveau dans l'app, via « Oublié ».",
    doneTitle: 'Mot de passe modifié',
    doneBody: "Tu peux maintenant te connecter à l'app AllDocs avec ton nouveau mot de passe. Par sécurité, les sessions sur les autres appareils ont été fermées.",
    failed: "Impossible d'enregistrer. Réessaie.",
  },
}

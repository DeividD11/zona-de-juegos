-- Configuración del envío real de recuperación de contraseña.
-- Ejecutar SOLO en Supabase SQL Editor después de verificar Vault y pg_net.
-- Sustituye los placeholders en una copia local; no guardes valores reales en Git.
select vault.create_secret('REPLACE_WITH_RESEND_API_KEY', 'password_reset_resend_api_key', 'API key de Resend para recuperación');
select vault.create_secret('REPLACE_WITH_VERIFIED_SENDER@example.com', 'password_reset_from_email', 'Remitente verificado para recuperación');
select vault.create_secret('https://deividd11.github.io/zona-de-juegos/reset-password.html', 'password_reset_app_url', 'URL pública de reset-password.html');

select name from vault.decrypted_secrets
where name in ('password_reset_resend_api_key','password_reset_from_email','password_reset_app_url')
order by name;

# install-infisical.ps1 — Windows PowerShell
# Run as Administrator or normal user

# 1. Generate keys
$ENCRYPTION_BYTES = [byte[]]::new(32)
$AUTH_BYTES       = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($ENCRYPTION_BYTES)
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($AUTH_BYTES)
$ENCRYPTION = [Convert]::ToBase64String($ENCRYPTION_BYTES)
$AUTH       = [Convert]::ToBase64String($AUTH_BYTES)

#kubectl create secret generic infisical-secrets -n infisical `
#  --from-literal=ENCRYPTION_KEY="<generated-ENCRYPTION_KEY>" `
#  --from-literal=AUTH_SECRET="<generated-AUTH_SECRET>" `
#  --from-literal=SITE_URL="https://infisical.internal.legohunter.io"

kubectl create secret generic infisical-secrets -n infisical `
  --from-literal=SITE_URL="https://infisical.internal.legohunter.io" `
  --from-literal=ENCRYPTION_KEY="$ENCRYPTION" `
  --from-literal=AUTH_SECRET="$AUTH"

#
# 4. Deploy (values.yaml must be in same folder)
#helm upgrade --install infisical infisical/infisical-standalone -n infisical -f helm-infisical-values.yaml --wait
#
#Write-Host "`nVAULT READY! Open: https://infisical.internal.legohunter.io"
#Write-Host "Login: admin / admin"
#

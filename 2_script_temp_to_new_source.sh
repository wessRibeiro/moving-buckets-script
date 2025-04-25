#!/bin/bash

# ENCERRA O SCRIPT CASO QUALQUER COMANDO FALHE
set -e

#SETTINGS
SOURCE_BUCKET=""
TEMP_BUCKET=""
SOURCE_PROJECT=""
DESTINATION_PROJECT=""
SOURCE_LOCATION=""
DESTINATION_LOCATION=""
IAM_POLICY_FILE="policies.json"

# CORES PARA LOG
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

error_exit() {
  echo -e "\033[0;31mErro: $1. Encerrando.\033[0m"
  exit 1
}

# Verifica se o bucket existe
bucket_exists() {
  local project_id="$1"
  local bucket_name="$2"
  
  gcloud storage buckets list --project="$project_id" \
    --filter="name:$bucket_name" \
    --format="value(name)" | grep -q "^$bucket_name$"
}

read -p "Tem certeza que deseja remover o bucket '$SOURCE_PROJECT/gs://$SOURCE_BUCKET'? Digite 'yes' para confirmar: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  error "Operação cancelada pelo usuário. O bucket não foi removido."
fi

# [5/9] Remoção do bucket original
log "[5/9] Removendo bucket original..."
if bucket_exists "$SOURCE_PROJECT" "$SOURCE_BUCKET"; then
  CMD="gcloud storage rm --recursive gs://$SOURCE_BUCKET"
  log "Executando: $CMD"
  eval "$CMD"
fi

# [6/9] Verificar e Recriação do bucket original no novo projeto
log "[6/9] Verificando e recriando bucket original no novo projeto..."

if bucket_exists "$SOURCE_PROJECT" "$SOURCE_BUCKET"; then
  echo -e "\n${GREEN}✅ Bucket ja foi removido: gs://$SOURCE_BUCKET ${NC}"
else
  CMD="gcloud storage buckets create gs://$SOURCE_BUCKET --project=$DESTINATION_PROJECT --location=$DESTINATION_LOCATION --lifecycle-file=lifecycle.json"
  log "\nExecutando: $CMD"
  eval "$CMD"
  echo -e "\n${GREEN}✅ criacao concluída com sucesso.${NC}"
fi

# [6.1/9] Exportar e aplicar política de IAM do bucket temporario
log "[6.1/9] Exportando política de IAM do bucket temporario..."

# Exporta a política atual do bucket temporario
log "Executando: gcloud storage buckets get-iam-policy gs://$TEMP_BUCKET --format=json > $IAM_POLICY_FILE"
gcloud storage buckets get-iam-policy gs://$TEMP_BUCKET --format=json > "$IAM_POLICY_FILE" || error "Falha ao obter IAM policy"

warn "[6.2/9] *** ATENÇÃO: Verifique as polices no arquivo $IAM_POLICY_FILE antes de aplica-las no gs://$SOURCE_BUCKET ***"
read -p "Pressione ENTER para continuar após a vericar."

# Verificar se o arquivo policy.json existe
if [[ ! -f "$IAM_POLICY_FILE" ]]; then
  echo "Erro: O arquivo $IAM_POLICY_FILE não foi encontrado!"
  exit 1
fi

# [6.3/9] aplicar política de IAM do bucket temporario
log "[6.3/9]Executando bindings"
# Iterar sobre cada binding no arquivo JSON
jq -c '.bindings[]' "$IAM_POLICY_FILE" | while read -r binding; do
  ROLE=$(echo "$binding" | jq -r '.role')
  MEMBERS=$(echo "$binding" | jq -r '.members[]')

  # Para cada membro dentro de um binding, adicionamos a política
  for MEMBER in $MEMBERS; do
    echo "Aplicando política: $MEMBER com a função $ROLE"
    
    # Executa o comando add-iam-policy-binding
    gcloud storage buckets add-iam-policy-binding gs://$SOURCE_BUCKET \
      --member="$MEMBER" \
      --role="$ROLE" || { echo "Erro ao adicionar política IAM para $MEMBER com a função $ROLE"; exit 1; }
  done
done

# [7/9] Copiando dados do bucket temporario para o original com estrutura de pastas
echo -e "\n${GREEN}[7/9] Copiando dados do bucket temporário para o original...${NC}"
gcloud storage cp --recursive gs://$TEMP_BUCKET/* gs://$SOURCE_BUCKET
echo -e "\n${GREEN}✅ Cópia concluída com sucesso.${NC}"

warn "[7/9] *** ATENÇÃO: Troque a referência de bucket da aplicação de $TEMP_BUCKET para $SOURCE_BUCKET ***"
read -p "Pressione ENTER para continuar após a troca."

# [8/9] Sincronização final para garantir consistência
log "[8/9] Sincronizando novamente para garantir consistência..."
CMD="gcloud storage rsync -r gs://$TEMP_BUCKET gs://$SOURCE_BUCKET"
log "\nExecutando: $CMD"
eval "$CMD"

read -p "Aprova a remocao do bucket 'gs://$TEMP_BUCKET'? Digite 'yes' para confirmar: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  error "Operação cancelada pelo usuário. O bucket não foi removido."
fi

# [9/9] Remoção do bucket original
log "[9/9] Removendo bucket gs://$TEMP_BUCKET..."
if bucket_exists "$DESTINATION_PROJECT" "$TEMP_BUCKET"; then
  CMD="gcloud storage rm --recursive gs://$TEMP_BUCKET"
  log "Executando: $CMD"
  eval "$CMD"
fi

log "✔️ Migração concluída com sucesso."

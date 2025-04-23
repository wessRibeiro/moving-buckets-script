#!/bin/bash

# ENCERRA O SCRIPT CASO QUALQUER COMANDO FALHE
set -e

#SETTINGS
SOURCE_BUCKET=""
TEMP_BUCKET=""
PROJECT_ORIGEM=""
PROJECT_DESTINO=""
LOCATION_ORIGEM="us-east1"
LOCATION_DESTINO="southamerica-east1"
IAM_POLICY_FILE="policy.json"

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
  local project_id="$PROJECT_DESTINO"
  local bucket_name="$TEMP_BUCKET"
  
  gcloud storage buckets list --project="$project_id" \
    --filter="name:$bucket_name" \
    --format="value(name)" | grep -q "^$bucket_name$"
}


# [1/9] Criar bucket temporário se não existir
log "[1/9] Verificando e criando bucket temporário..."
if bucket_exists "$PROJECT_DESTINO" "$TEMP_BUCKET"; then
  echo -e "\n${GREEN}✅ Bucket temporário já existe: gs://$TEMP_BUCKET ${NC}"
else
  CMD="gcloud storage buckets create gs://$TEMP_BUCKET --project=$PROJECT_DESTINO --location=$LOCATION_DESTINO --lifecycle-file=lifecycle.json"
  log "\nExecutando: $CMD"
  eval "$CMD"
  echo -e "\n${GREEN}✅ criacao concluída com sucesso.${NC}"
fi

# [1.2/9] Exportar e aplicar política de IAM do bucket original
log "[1.2/9] Exportando política de IAM do bucket original..."

# Exporta a política atual do bucket original
log "Executando: gcloud storage buckets get-iam-policy gs://$SOURCE_BUCKET --format=json > $IAM_POLICY_FILE"
gcloud storage buckets get-iam-policy gs://$SOURCE_BUCKET --format=json > "$IAM_POLICY_FILE" || error "Falha ao obter IAM policy"

warn "[1.2/9] *** ATENÇÃO: Verifique as polices no arquivo $IAM_POLICY_FILE antes de aplica-las no $TEMP_BUCKET ***"
read -p "Pressione ENTER para continuar após a vericar."

# Verificar se o arquivo policy.json existe
if [[ ! -f "$IAM_POLICY_FILE" ]]; then
  echo "Erro: O arquivo $IAM_POLICY_FILE não foi encontrado!"
  exit 1
fi

# [1.3/9] aplicar política de IAM do bucket original
log "[1.3/9]Executando bindings"
# Iterar sobre cada binding no arquivo JSON
jq -c '.bindings[]' "$IAM_POLICY_FILE" | while read -r binding; do
  ROLE=$(echo "$binding" | jq -r '.role')
  MEMBERS=$(echo "$binding" | jq -r '.members[]')

  # Para cada membro dentro de um binding, adicionamos a política
  for MEMBER in $MEMBERS; do
    echo "Aplicando política: $MEMBER com a função $ROLE"
    
    # Executa o comando add-iam-policy-binding
    gcloud storage buckets add-iam-policy-binding gs://$TEMP_BUCKET \
      --member="$MEMBER" \
      --role="$ROLE" || { echo "Erro ao adicionar política IAM para $MEMBER com a função $ROLE"; exit 1; }
  done
done

# [2/9] Copiando dados do bucket original para o temporário com estrutura de pastas
echo -e "${GREEN}[2/9] Copiando dados do bucket original para o temporário...${NC}"
gcloud storage cp --recursive gs://$SOURCE_BUCKET/* gs://$TEMP_BUCKET
echo -e "\n${GREEN}✅ Cópia concluída com sucesso.${NC}"

warn "[3/9] *** ATENÇÃO: Troque a referência de bucket da aplicação de $SOURCE_BUCKET para $TEMP_BUCKET ***"
read -p "Pressione ENTER para continuar após a troca."

# [4/9] Sincronização final para garantir consistência
log "[4/9] Sincronizando novamente para garantir consistência..."
CMD="gcloud storage rsync -r gs://$SOURCE_BUCKET gs://$TEMP_BUCKET"
log "\nExecutando: $CMD"
eval "$CMD"
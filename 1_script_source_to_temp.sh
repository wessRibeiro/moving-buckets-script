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
  echo -e "\033[0;31mErro: $1. Exiting.\033[0m"
  exit 1
}

# Check if the bucket exists
bucket_exists() {
  local project_id="$DESTINATION_PROJECT"
  local bucket_name="$TEMP_BUCKET"
  
  gcloud storage buckets list --project="$project_id" \
    --filter="name:$bucket_name" \
    --format="value(name)" | grep -q "^$bucket_name$"
}


# [1/9] Create temporary bucket if it doesn't exist
log "[1/9] Checking and creating temporary bucket..."
if bucket_exists "$DESTINATION_PROJECT" "$TEMP_BUCKET"; then
  echo -e "\n${GREEN}✅ Temporary bucket already exists: gs://$TEMP_BUCKET ${NC}"
else
  CMD="gcloud storage buckets create gs://$TEMP_BUCKET --project=$DESTINATION_PROJECT --location=$DESTINATION_LOCATION --lifecycle-file=lifecycle.json"
  log "\nExecuting: $CMD"
  eval "$CMD"
  echo -e "\n${GREEN}✅ Bucket successfully created.${NC}"
fi

# [1.2/9] Export and apply IAM policy from the original bucket
log "[1.2/9] Exporting IAM policy from the original bucket..."

log "Executing: gcloud storage buckets get-iam-policy gs://$SOURCE_BUCKET --format=json > $IAM_POLICY_FILE"
gcloud storage buckets get-iam-policy gs://$SOURCE_BUCKET --format=json > "$IAM_POLICY_FILE" || error "Failed to retrieve IAM policy"

warn "[1.2/9] ⚠️ ATTENTION: Review the policies in $IAM_POLICY_FILE before applying them to $TEMP_BUCKET"
read -p "Press ENTER to continue after reviewing."

# Check if policy.json exists
if [[ ! -f "$IAM_POLICY_FILE" ]]; then
  echo "Erro: O arquivo $IAM_POLICY_FILE was not found!"
  exit 1
fi

# [1.3/9] Apply IAM policy from the original bucket
log "[1.3/9] Applying IAM bindings..."
# Iterate over each binding in the JSON file
jq -c '.bindings[]' "$IAM_POLICY_FILE" | while read -r binding; do
  ROLE=$(echo "$binding" | jq -r '.role')
  MEMBERS=$(echo "$binding" | jq -r '.members[]')
  # For each member in the binding, apply the policy
  for MEMBER in $MEMBERS; do
    echo "Applying policy: $MEMBER with role $ROLE"
    
    gcloud storage buckets add-iam-policy-binding gs://$TEMP_BUCKET \
      --member="$MEMBER" \
      --role="$ROLE" || { echo "Erro ao adicionar política IAM para $MEMBER com a função $ROLE"; exit 1; }
  done
done

# [2/9] Copy data from original to temporary bucket (preserving folder structure)
echo -e "${GREEN}[2/9] Copying data from original bucket to temporary bucket...${NC}"
gcloud storage cp --recursive gs://$SOURCE_BUCKET/* gs://$TEMP_BUCKET
echo -e "\n${GREEN}✅ Copy completed successfully.${NC}"

warn "[3/9] ⚠️ ATTENTION: Update the application bucket reference from $SOURCE_BUCKET to $TEMP_BUCKET"
read -p "Press ENTER to continue after updating."

# [4/9] Final sync to ensure consistency
log "[4/9] Syncing again to ensure consistency..."
CMD="gcloud storage rsync -r gs://$SOURCE_BUCKET gs://$TEMP_BUCKET"
log "\nExecuting: $CMD"
eval "$CMD"

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
  local project_id="$1"
  local bucket_name="$2"
  
  gcloud storage buckets list --project="$project_id" \
    --filter="name:$bucket_name" \
    --format="value(name)" | grep -q "^$bucket_name$"
}

read -p "Are you sure you want to remove the bucket '$SOURCE_PROJECT/gs://$SOURCE_BUCKET'? Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  error "Operation cancelled by user. Bucket was not removed."
fi

# [5/9] Remove the original bucket
log "[5/9] Removing original bucket..."
if bucket_exists "$SOURCE_PROJECT" "$SOURCE_BUCKET"; then
  CMD="gcloud storage rm --recursive gs://$SOURCE_BUCKET"
  log "Executing: $CMD"
  eval "$CMD"
fi

# [6/9] Check and recreate the original bucket in the new project
log "[6/9] Checking and recreating original bucket in the new project..."

if bucket_exists "$SOURCE_PROJECT" "$SOURCE_BUCKET"; then
  echo -e "\n${GREEN}✅ Bucket already removed: gs://$SOURCE_BUCKET ${NC}"
else
  CMD="gcloud storage buckets create gs://$SOURCE_BUCKET --project=$DESTINATION_PROJECT --location=$DESTINATION_LOCATION --lifecycle-file=lifecycle.json"
  log "\nExecuting: $CMD"
  eval "$CMD"
  echo -e "\n${GREEN}✅ Bucket created successfully.${NC}"
fi

# [6.1/9] Export and apply IAM policy from temporary bucket
log "[6.1/9] Exporting IAM policy from temporary bucket..."

# Export current IAM policy from temporary bucket
log "Executing: gcloud storage buckets get-iam-policy gs://$TEMP_BUCKET --format=json > $IAM_POLICY_FILE"
gcloud storage buckets get-iam-policy gs://$TEMP_BUCKET --format=json > "$IAM_POLICY_FILE" || error "Failed to get IAM policy"

warn "[6.2/9] ⚠️ IMPORTANT: Review the policies in $IAM_POLICY_FILE before applying them to gs://$SOURCE_BUCKET ***"
read -p "Press ENTER to continue after reviewing."

# Check if the IAM policy file exists
if [[ ! -f "$IAM_POLICY_FILE" ]]; then
  echo "Error: File $IAM_POLICY_FILE not found!"
  exit 1
fi

# [6.3/9] Apply IAM policies to the new bucket
log "[6.3/9] Applying IAM bindings..."
jq -c '.bindings[]' "$IAM_POLICY_FILE" | while read -r binding; do
  ROLE=$(echo "$binding" | jq -r '.role')
  MEMBERS=$(echo "$binding" | jq -r '.members[]')

  for MEMBER in $MEMBERS; do
    echo "Applying policy: $MEMBER with role $ROLE"
  
    gcloud storage buckets add-iam-policy-binding gs://$SOURCE_BUCKET \
      --member="$MEMBER" \
      --role="$ROLE" || { echo "Error applying IAM policy for $MEMBER with role $ROLE"; exit 1; }
  done
done

# [7/9] Copy data from the temporary bucket to the new bucket
echo -e "\n${GREEN}[7/9] Copying data from temporary bucket to original bucket...${NC}"
gcloud storage cp --recursive gs://$TEMP_BUCKET/* gs://$SOURCE_BUCKET
echo -e "\n${GREEN}✅ Copy completed successfully.${NC}"

warn "[7/9] ⚠️ IMPORTANT: Switch your application’s bucket reference from $TEMP_BUCKET back to $SOURCE_BUCKET"
read -p "Press ENTER after completing the switch."

# [8/9] Final sync to ensure consistency
log "[8/9] Performing final sync to ensure consistency..."
CMD="gcloud storage rsync -r gs://$TEMP_BUCKET gs://$SOURCE_BUCKET"
log "\nExecuting: $CMD"
eval "$CMD"

read -p "Do you approve the deletion of bucket 'gs://$TEMP_BUCKET'? Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  error_exit "Operation cancelled by user. Temporary bucket was not removed."
fi

# [9/9] Remove the temporary bucket
log "[9/9] Removing bucket gs://$TEMP_BUCKET..."
if bucket_exists "$DESTINATION_PROJECT" "$TEMP_BUCKET"; then
  CMD="gcloud storage rm --recursive gs://$TEMP_BUCKET"
  log "Executing: $CMD"
  eval "$CMD"
fi

log "✔️ Migration completed successfully."

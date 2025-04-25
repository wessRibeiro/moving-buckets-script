# 📦 moving-buckets-script

This project contains two Bash scripts that automate the migration of buckets in Google Cloud Storage between projects, focusing on preserving structure, data, and permissions securely — without noticeable downtime for the application.

---

## 🗂️ Project Structure

```bash
.
├── 1_script_source_to_temp.sh       # Copies data from the original bucket to a temporary bucket
├── 2_script_temp_to_new_source.sh   # Restores data from the temporary bucket to a recreated bucket
├── lifecycle.json                   # Defines lifecycle rule (deletes objects after 365 days)
├── policies.json                    # Contains extracted and applied IAM permissions for buckets
```

## ⚙️ Prerequisites

- Have the Google Cloud SDK (gcloud) installed and authenticated.
- Have jq installed for reading JSON files.
- Sufficient permissions in both source and destination projects (IAM Admin or Storage Admin roles).
  
---

## 🚀 How to Use

## Step 1️⃣: Copy data from the original bucket to a temporary bucket

Run the script:

```bash
bash 1_script_source_to_temp.sh
```

This script will:
- Check if the temporary bucket exists and create it if not.
- Export and apply the IAM permissions from the original bucket to the temporary bucket.
- Copy the data from the original bucket to the temporary bucket.
- Prompt you to point the application to the temporary bucket.
- Perform a final sync to ensure data consistency.

---

## Step 2️⃣: Restore the data to the new bucket (recreated with the same name)

Run the script:

```bash
bash 2_script_temp_to_new_source.sh
```

This script will:

- Request confirmation to delete the original bucket.
- Recreate the original bucket with the same settings in the new project.
- Reapply the IAM permissions exported from the temporary bucket.
- Copy the data from the temporary bucket to the newly recreated original bucket.
- Prompt you to point the application back to the original bucket.
- Perform a final sync of the data.
- Request confirmation to delete the temporary bucket.

---

## 🛡️ Security and Reliability

- The scripts require explicit confirmation (yes) before deleting any bucket.
- All permissions from the original bucket are exported to policies.json and reapplied using gcloud storage buckets add-iam-policy-binding.
- The folder and file structure inside the buckets is preserved.
- Final synchronizations ensure that no changes are lost during the process.

---

## 📄 lifecycle.json

```json
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
```


This lifecycle rule is applied to the new buckets to delete objects older than 365 days.
It can be modified according to your project’s needs.

---

## 🧾 About the policies.json File

The policies.json file is an example structure of an IAM policy generated based on the permissions of the original bucket.

As the scripts are executed, this file can be manually edited to apply only the necessary permissions to the new bucket.

### Example structure:

```json
{
  "bindings": [
    {
      "members": [
        "user:exemplo@empresa.com"
      ],
      "role": "roles/storage.objectViewer"
    }
  ]
}
```
---

## ℹ️ Notes

- Make sure to fill in the variables `SOURCE_BUCKET`, `TEMP_BUCKET`, `SOURCE_PROJECT`, `DESTINATION_PROJECT`, `SOURCE_LOCATION`, and `DESTINATION_LOCATION` in both scripts before running them.
- The  `"members"` field inside `policies.json` must be filled correctly with valid IAM members (users, service accounts, groups, etc.).
---

## ✅ Full Example of Usage

```bash
# Etapa 1
vim 1_script_source_to_temp.sh   # configure your variables
bash 1_script_source_to_temp.sh

# Etapa 2
vim 2_script_temp_to_new_source.sh  # configure your variables
bash 2_script_temp_to_new_source.sh
```

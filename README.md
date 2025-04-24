# 📦 moving-buckets-script

Este projeto contém dois scripts bash que automatizam a migração de buckets no Google Cloud Storage entre projetos, com foco em manter a estrutura, dados e permissões de forma segura, **sem downtime perceptível para a aplicação**.

---

## 🗂️ Estrutura do projeto

```bash
.
├── 1_script_source_to_temp.sh       # Copia dados do bucket original para um bucket temporário
├── 2_script_temp_to_new_source.sh   # Restaura os dados do bucket temporário para um bucket recriado
├── lifecycle.json                   # Define regra de ciclo de vida (exclusão de objetos após 365 dias)
├── policies.json                    # Contém as permissões extraídas e aplicadas aos buckets


## ⚙️ Pré-requisitos

- Ter o SDK do Google Cloud (`gcloud`) instalado e autenticado.
- Ter o `jq` instalado para leitura de arquivos JSON.
- Permissões suficientes nos projetos de origem e destino (`IAM Admin` ou `Storage Admin`).

---

## 🚀 Como usar

## Etapa 1️⃣: Copiar dados do bucket original para bucket temporário

Execute o script:

```bash
bash 1_script_source_to_temp.sh
```

Esse script irá:

- Verificar se o bucket temporário existe, e criar caso não.
- Exportar e aplicar as permissões IAM do bucket original no temporário.
- Copiar os dados do bucket original para o bucket temporário.
- Solicitar a troca de referência da aplicação para o bucket temporário.
- Fazer uma sincronização final para garantir consistência.

---

## Etapa 2️⃣: Restaurar os dados no novo bucket (recriado com mesmo nome)

Execute o script:

```bash
bash 2_script_temp_to_new_source.sh
```

Esse script irá:

- Solicitar confirmação para remover o bucket original.
- Recriar o bucket original com as mesmas configurações.
- Aplicar novamente as permissões IAM exportadas do temporário.
- Copiar os dados do bucket temporário para o bucket recriado.
- Solicitar a troca de referência da aplicação de volta para o bucket original.
- Realizar uma sincronização final dos dados.
- Solicitar confirmação e excluir o bucket temporário.

---

## 🛡️ Segurança e confiabilidade

- Os scripts exigem confirmação explícita (`yes`) antes de remover qualquer bucket.
- Todas as permissões do bucket original são exportadas para `policies.json` e reaplicadas via `gcloud storage buckets add-iam-policy-binding`.
- A estrutura dos arquivos dentro dos buckets é preservada.
- Há sincronizações finais para garantir que nenhuma alteração seja perdida durante o processo.

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


Essa política é aplicada nos buckets novos para excluir objetos com mais de 365 dias e pode ser alterada conforme necessidade.

---

## 🧾 Sobre o arquivo `policies.json`

O arquivo `policies.json` é um **exemplo de estrutura de política IAM** gerado com base nas permissões do bucket original.

À medida que os scripts são executados, esse arquivo pode ser **editado manualmente** para aplicar apenas as permissões que forem realmente necessárias no novo bucket.

### Exemplo de estrutura:

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

---

## ℹ️ Observações

- Certifique-se de preencher as variáveis `SOURCE_BUCKET`, `TEMP_BUCKET`, `PROJECT_ORIGEM`, `PROJECT_DESTINO`, `LOCATION_ORIGEM`, e `LOCATION_DESTINO` nos dois scripts antes de executá-los.
- O campo `"members"` no `policies.json` deve ser preenchido corretamente com os membros válidos do IAM (usuários, contas de serviço, grupos etc.).

---

## ✅ Exemplo de uso completo

```bash
# Etapa 1
vim 1_script_source_to_temp.sh  # configure as variáveis
bash 1_script_source_to_temp.sh

# Etapa 2
vim 2_script_temp_to_new_source.sh  # configure as variáveis
bash 2_script_temp_to_new_source.sh
```

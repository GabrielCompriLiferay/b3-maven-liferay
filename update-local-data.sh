#!/bin/bash

Red=`tput setaf 1`
Green=`tput setaf 2`
Yellow=`tput setaf 3`
Color_Off=`tput sgr0`

# Verifica se o id do backup a ser baixado foi informado na chamada do script
if [ $# -eq 0 ]; then
  echo "O id do backup do DXP cloud precisa ser informado. Abaixo segue um exemplo da forma correta de se utilizar este script:"
  echo "$0 dxpcloud-ekmwibolkxvixaajfv-202312090000"
  exit 1
fi

# Verifica se a CLI lcp está instalada e, caso necessário, realiza a instalação
if ! lcp version >/dev/null 2>&1; then
  echo "Realizando a instalação da CLI do DXP Cloud"
  curl https://cdn.liferay.cloud/lcp/stable/latest/install.sh -fsSL | bash
fi

DXP_CLOUD_PROJECT="b3dxp"
DXP_CLOUD_ENV="dev"
DXP_CLOUD_BACKUP_ID=$1
DOCKER_DATABASE_CONTAINER_NAME="local-env-database-1"
MYSQL_ROOT_PASSWD="root"
CURRENT_DATE_TIME_STR=$(date "+%F_%T")
LOCAL_BACKUP_FOLDER="./local_backup/$CURRENT_DATE_TIME_STR"

echo ""
echo ">> Realizando download do backup do DXP Cloud..."
echo ""

lcp backup download --backupId $DXP_CLOUD_BACKUP_ID --project $DXP_CLOUD_PROJECT --environment $DXP_CLOUD_ENV --database --doclib
DXPCLOUD_BACKUP_FOLDER=$(ls . | grep $DXP_CLOUD_BACKUP_ID)

echo ""
echo ">> Download do backup finalizado $Green✔$Color_Off"
echo ">> Extraindo o dump do database..."

# Monta o nome do arquivo gzip, inserindo "database" antes do trecho final com a data do backupId
IFS='-' read -ra backup_id_parts <<< "$DXP_CLOUD_BACKUP_ID"
backup_file_name="${backup_id_parts[0]}-${backup_id_parts[1]}-database-${backup_id_parts[2]}"

# Unzipa o arquivo com o dump do banco
cd ./$DXPCLOUD_BACKUP_FOLDER/database
gunzip -k $backup_file_name.gz
mv $backup_file_name lportal.sql
cd ../../

echo ">> Extração do dump finalizada $Green✔$Color_Off"
echo ">> Derrubando o stack local e iniciando o serviço database..."
echo ""

# Para o stack local, caso esteja rodando e inicia apenas o serviço do banco
docker compose down
docker compose up database -d

sleep 5

echo ""
echo ">> Realizando backup do banco local e carregando o dump do DXP Cloud..."
echo ""

# Realizando backup dos dados atuais e carrega o dump do DXP Cloud no container mysql
mkdir -p $LOCAL_BACKUP_FOLDER
docker container exec $DOCKER_DATABASE_CONTAINER_NAME bash -c "mysqldump -u root -p$MYSQL_ROOT_PASSWD lportal > /var/lib/mysql/lportal.sql"
docker container cp $DOCKER_DATABASE_CONTAINER_NAME:/var/lib/mysql/lportal.sql ./$LOCAL_BACKUP_FOLDER
docker container exec $DOCKER_DATABASE_CONTAINER_NAME bash -c "rm -f /var/lib/mysql/lportal.sql"
docker container cp ./$DXPCLOUD_BACKUP_FOLDER/database/lportal.sql $DOCKER_DATABASE_CONTAINER_NAME:/var/lib/mysql/lportal.sql
docker container exec $DOCKER_DATABASE_CONTAINER_NAME bash -c "mysql -u root -p$MYSQL_ROOT_PASSWD < /var/lib/mysql/lportal.sql"
echo ""
docker compose down

echo ""
echo ">> Backup do banco local realizado e dump DXP Cloud carregado $Green✔$Color_Off"

mv ./volumes/liferay/data/document_library $LOCAL_BACKUP_FOLDER
mv ./$DXPCLOUD_BACKUP_FOLDER/doclib ./volumes/liferay/data
cd ./volumes/liferay/data
mv doclib document_library
cd ../../../
rm -Rf ./$DXPCLOUD_BACKUP_FOLDER

echo ">> Backup do document library local realizado e dump do document library carregado $Green✔$Color_Off"
echo ">> O backup dos seus dados locais (banco e document library) foi salvo em: $Red $LOCAL_BACKUP_FOLDER $Color_Off $Green✔$Color_Off"
echo ">> Dados locais atualizados com sucesso. $Green✔$Color_Off"
echo ">>$Yellow ATENÇÃO: Inicie seu stack local, faça login no liferay e execute uma reindexação completa do portal."
echo ""

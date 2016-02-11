#!/bin/sh
clear

## VARIABLES ##
# Fechas #
hoy=`date '+%d-%m-%Y'`                                              ## NO TOCAR!! # Fecha de hoy
fecha="$(date '+%A_%d-%m-%Y_%H:%M')"                                ## NO TOCAR!! # Fecha y hora actual
ayer=`date '+%d-%m-%Y' -d "1 day ago"`                              ## NO TOCAR!! # Fecha del día anterior
mes=`date '+%d-%m-%Y' -d "30 days ago"`                             ## NO TOCAR!! # Fecha 1 mes anterior

# Directorios #
dominio=""                                                  # Nombre de nuestro dominio
dir="$HOME/Backups/$dominio"                                        # Ruta del directorio donde se guardan todas las copias
origenDesWWW=""            # Ruta de archivos a salvar - RUTA ABSOLUTA
destinoDesWWW="$dir/destinoDesWWW/$hoy"                             ## NO TOCAR!! # Ruta donde se guarda el backup
anteriorDesWWW="$dir/anteriorDesWWW/$ayer"                          ## NO TOCAR!! # Ruta del backup del día anterior
destinoCompWWW="$dir/destinoCompWWW/$hoy"                           ## NO TOCAR!! # Ruta donde se guarda el backup comprimido
anteriorCompWWW="$dir/anteriorCompWWW/$ayer"                        ## NO TOCAR!! # Ruta del backup comprimido del día anterior
destinoCompDB="$dir/destinoCompDB"                                  ## NO TOCAR!! # Ruta del backup de la base de datos
logs="$dir/Logs"                                                    ## NO TOCAR!! # Ruta donde se guardan los logs

# Borrado de archivos antiguos #
diasBorraDB="120"                                                  # Dias a los que se borrarán las bases de datos antiguas
diasBorraWWW="60"                                                   # Dias a los que se borrarán los archivos web descomprimidos
diasBorraWWWcomp="120"                                              # Dias a los que se borrarán los archivos web comprimidos

# Datos conexión ssh #
sshuser=""								                                # Usuario para la conexión ssh
sshpass=""								                                # Contraseña para la conexión ssh
sshhost=""                                             # Dirección conexión ssh

# Datos conexión db #
dbuser=""								                                    # Usuario para la conexión mysql
dbpass=""								                                  # Contraseña para la conexión mysql
dbhost=""								                            # Dirección de conexión mysql de nuestro proveedor
dbname=""								                                  # Nombre de la base de datos

# Varias #
rutas=(" $destinoDesWWW $anteriorDesWWW $destinoCompWWW $anteriorCompWWW $destinoCompDB $logs " )     ## NO TOCAR!! # Para crear los directorios
dep=(" openssh mariadb expect tar rsync curl" )                     ## NO TOCAR!! # Dependencias necesarias para el script
variables=(" sshuser sshpass sshhost dbuser dbpass dbhost dbname hoy fecha ayer mes dominio dir origenDesWWW destinoDesWWW anteriorDesWWW destinoCompWWW anteriorCompWWW destinoCompDB logs diasBorraDB diasBorraWWW diasBorraWWWcomp ")

## COMIEZO DEL SCRIPT ##

# Comprobar e instalar paquetes necesarios #
for d in ${dep[*]}
do
  if ! (pacman -Q $d >/dev/null);
  then
    insta=$insta" "$d
  fi
done
if [ -n "$insta" ]
  then
  echo "Necesitamos instalar: $insta"
  sleep 5
  sudo pacman -Sy $insta --noconfirm
fi

# Crea la clave ssh si no está creada en nuestro equipo
if [ ! -f $HOME/.ssh/idrsa-1 ]; then
  ssh-keygen -t rsa -N "$sshpass" -f $HOME/.ssh/idrsa-1
	expect << EOF
		spawn ssh-add $HOME/.ssh/idrsa-1
		expect "Enter passphrase for $HOME/.ssh/idrsa-1:"
		send "$sshpass\r"
		expect eof
EOF
fi

# Introducimos en el remoto la llave ssh si no existe
expect -c "
  log_user 0
	spawn ssh-copy-id -i $HOME/.ssh/idrsa-1.pub ${sshuser}@${sshhost}
  match_max 100000
	expect \"*?assword:*\" { send -- \"$sshpass\r\"}
	sleep 1
	log_user 1
	exit
"

# Comprobamos que las variables obligatorias estén completas #
for var in $variables; do
  if [ -z ${!var} ] ; then
		echo "Para poder ejecutar el script debes rellenar todas las variables"
    read -rsp $'Pulsa cualquier tecla para cerrar el script\n' -n1 key
		exit
	fi
done

# Comprobamos si tenemos los directorios para las copias, de lo contrario los crea #
for f in $rutas; do
	[ -d $rutas 2> /dev/null ] && direc+="$f " || ndirec+="$f "
done
mkdir -p $ndirec

## ELIMINAMOS LOS BACKUPS ANTIGUOS ##
find $destinoCompDB/* -mtime +$diasBorraDB -type d -exec rm -f \{\} \;
find $destinoDesWWW/* -mtime +$diasBorraWWW -type d -exec rm -f \{\} \;
find $destinoCompWWW/* -mtime +$diasBorraWWWcomp -type d -exec rm -f \{\} \;

# Backup de la base de datos #
mkdir -p $destinoCompDB/$hoy
ssh $sshuser@$sshhost "mysqldump -h $dbhost -u $dbuser -p$dbpass -B $dbname" | gzip > $destinoCompDB/$hoy/$dbname.sql.gz > $logs/backupDB-$fecha.log 2>&1

#Ejecutar respaldo incremental
rsync -avz --delete --progress --link-dest=$anteriorDesWWW -e "ssh" $sshuser@$sshhost:$origenDesWWW $destinoDesWWW > $logs/backupWWW-$fecha.log 2>&1
tar cjvf $destinoCompWWW/$hoy.tar.bz2 $destinoDesWWW/

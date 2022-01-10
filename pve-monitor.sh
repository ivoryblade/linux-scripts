#!/bin/bash
SHELL=/bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin/
export DISPLAY=:0.0

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
function checkinstalldependencies () {
  packages=("$@")
  for i in "${packages[@]}";
    do
      if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 0 ];
      then
        apt-get -y install $i;
        echo "Installed $i successfuly!"
      fi
    done
}
function checkinstalltelegramnotify () {
  if [[ ! -e /usr/local/sbin/telegram-notify ]]; then
      wget https://raw.githubusercontent.com/NicolasBernaerts/debian-scripts/master/telegram/telegram-notify-install.sh -O - | sh

      rm /etc/telegram-notify.conf
      ln -s $DIR/telegram-notify.conf /etc
      echo "Telegram-notify installed successfuly!"
  fi
}
function MessageAddHostInformation () {
  Message="$Message<b>Имя хоста:</b> <code>$(hostname)</code>\n"
  Message="$Message<b>Процессор(ы): <code>$(lscpu | grep "NUMA node(s):" | awk '{print $3}') x $(lscpu | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p')</code></b>\n"
  Message="$Message<b>Версия PVE: <code>$(dpkg -l | grep pve-manager | awk '{print $3}')</code></b>\n"
  Message="$Message<b>Версия ядра: <code>$(uname -r)</code></b>\n"
  Message="$Message<b>Дата:</b> <code>$(date +'%d-%m-%Y %H:%M')</code>\n"
  Message="$Message<b>Внешний адрес сервера:</b> <code>$(curl -s http://whatismyip.akamai.com/)</code>\n"
  Message="$Message<b>Локальные сетевые интерфейсы:</b>\n"
  #Message="$Message<code>$(printf "%-10s %-16s" "INTERFACE" "IP")</code>\n"
  ifaces=($(ifconfig -a | sed 's/[ \t].*//;/^\(lo\|\)$/d' | sed -E 's/\:+//g'))

  for iface in "${ifaces[@]}"
  do
    ifaceip=$(ifconfig $iface | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
    if [[ $ifaceip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      Message="$Message<code>$(printf "%-10s %-16s" "$iface" "$ifaceip")</code>\n"
    fi
  done
}
function MessageAddHostDiskInfo () {
  drives=($(lsblk --nodeps -n -o name | grep -v '^loop' | grep -v '^zd' | grep -v '^nvme' | grep -v '^sr'))
  if (( ${#drives[@]} != 0 )); then
    for drive in "${drives[@]}"
    do
          if [[ $(smartctl -a /dev/$drive | grep "Rotation") == *"Solid"* ]]; then
                  SSDdrives+=($drive)
                  #echo $drive" is SSD"
          elif [[ $(smartctl -a /dev/$drive | grep "Transport protocol:" | awk -F':' '{print $2}' | sed -e 's/^[ \t]*//') == *"SAS"* ]]; then
                  SASdrives+=($drive)
                  #echo $drive" is SAS"
          else
                  HDDdrives+=($drive)
                  #echo $drive" is HDD"
          fi

    done


    if (( ${#HDDdrives[@]} != 0 )); then
          hdd_diskstatusformat="%-30s %-20s %-8s %-8s %-5s %-5s %-5s"
          Message="$Message<b>Состояние HDD Дисков:</b>\n\n <code>$(printf "$hdd_diskstatusformat" "MODEL" "SERIAL" "SMART" "POH" "REC" "CPS" "OU")</code>\n"
          for hdd_drive in "${HDDdrives[@]}"
          do
                          hdd_drive=$(echo /dev/$hdd_drive)
                          Message="$Message <code>$(printf "$hdd_diskstatusformat" "$(hdparm -I $hdd_drive | grep "Model Number" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -a $hdd_drive | grep "Serial Number:" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -H $hdd_drive 2>/dev/null | grep '^SMART overall' | awk '{ print $6 }')" "$(smartctl -a $hdd_drive | grep "Power_On_Hours" | awk '{print $NF}')h" "$(smartctl -a $hdd_drive | grep "Reallocated_Event_Count" | awk '{print $NF}')" "$(smartctl -a $hdd_drive | grep "Current_Pending_Sector" | awk '{print $NF}')" "$(smartctl -a $hdd_drive | grep "Offline_Uncorrectable" | awk '{print $NF}')")</code>\n"
          done
          Message="$Message\n"
    fi

    if (( ${#SSDdrives[@]} != 0 )); then
          ssd_diskstatusformat="%-30s %-20s %-8s %-8s %-5s"
          Message="$Message<b>Состояние SSD Дисков:</b>\n\n <code>$(printf "$ssd_diskstatusformat" "MODEL" "SERIAL" "SMART" "POH" "LIFETIME")</code>\n"
          for ssd_drive in "${SSDdrives[@]}"
          do
                          ssd_drive=$(echo /dev/$ssd_drive)
                          if [[ !  $(smartctl -a $ssd_drive | grep Wear | awk '{print $4}' |  sed 's/^0*//' ) == ""  ]]; then
                        		ssd_drive_lifetime="$(smartctl -a $ssd_drive | grep Wear | awk '{print $4}' |  sed 's/^0*//' )%"
                        	elif [[ !  $(smartctl -a $ssd_drive | grep SSD_Life_Left | awk '{print $4}' |  sed 's/^0*//' ) == ""  ]]; then
                        		ssd_drive_lifetime="$(smartctl -a $ssd_drive | grep "SSD_Life_Left" | awk '{print $4}' |  sed 's/^0*//' )%"
                        	else
                        		ssd_drive_lifetime="NA"
                        	fi
                          Message="$Message <code>$(printf "$ssd_diskstatusformat" "$(hdparm -I $ssd_drive | grep "Model Number" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -a $ssd_drive | grep "Serial Number:" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -H $ssd_drive 2>/dev/null | grep '^SMART overall' | awk '{ print $6 }')" "$(smartctl -a $ssd_drive | grep "Power_On_Hours" | awk '{print $NF}')h" $ssd_drive_lifetime)</code>\n"
          done
          Message="$Message\n"
    fi

    if (( ${#SASdrives[@]} != 0 )); then
          sas_diskstatusformat="%-30s %-20s %-8s %-10s %-5s"
          Message="$Message<b>Состояние SAS Дисков:</b>\n\n <code>$(printf "$sas_diskstatusformat" "MODEL" "SERIAL" "SMART" "POH" "NEC")</code>\n"
          for sas_drive in "${SASdrives[@]}"
          do
                          sas_drive=$(echo /dev/$sas_drive)
                          Message="$Message <code>$(printf "$sas_diskstatusformat" "$(smartctl -a $sas_drive | grep "Product:" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -a $sas_drive | grep "Serial number:" | awk -F":" '{ print $2 }' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g")" "$(smartctl -H $sas_drive 2>/dev/null | grep '^SMART Health Status' | awk '{ print $4 }')" "$(smartctl -a $sas_drive | grep "Accumulated power on time, hours:minutes" | awk '{print $NF}' | cut -f1 -d":")h" "$(smartctl -a $sas_drive | grep "Non-medium error count:" | awk '{print $NF}')")</code>\n"
          done
          Message="$Message\n"
    fi
  fi

  #########################

    if [[ ! $(ls /dev | grep "nvme") == "" ]]; then

    	Message="$Message<b>Состояние NVME Дисков:</b>\n"
    	Message="$Message\n<code>$(printf "%-35s %-20s %-10s %-7s" "MODEL" "SERIAL" "TBW" "WEAROUT")</code>\n"

    	for nvmedrive in /dev/nvme[0-99]
    	do
        if [ $(nvme smart-log $nvmedrive | grep percentage_used | awk '{print $3}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" | sed -E 's/\%+//g') -ge 100 ]
        then
          problems=1
          Message="$Message<code>$(printf "%-35s %-20s %-10s %-7s %-20s" "$(nvme id-ctrl $nvmedrive | grep "\bmn\b" | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" )" "$(nvme id-ctrl $nvmedrive | grep "\bsn\b" | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" )" "$(smartctl -A $nvmedrive | grep "Data Units Written:" |sed -E 's/(^|\])[^[]*($|\[)/ /g' | sed 's/^ *//')" "$(nvme smart-log $nvmedrive | grep percentage_used | awk '{print $3}' | sed -e 's/^[ \t]*//' |sed -e "s/[[:space:]]\+/ /g" ) " "</code>🚨<u>Срочно Заменить!</u>")\n"
        else
          Message="$Message<code>$(printf "%-35s %-20s %-10s %-7s" "$(nvme id-ctrl $nvmedrive | grep "\bmn\b" | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" )" "$(nvme id-ctrl $nvmedrive | grep "\bsn\b" | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" )" "$(smartctl -A $nvmedrive | grep "Data Units Written:" |sed -E 's/(^|\])[^[]*($|\[)/ /g' | sed 's/^ *//')" "$(nvme smart-log $nvmedrive | grep percentage_used | awk '{print $3}' | sed -e 's/^[ \t]*//' | sed -e "s/[[:space:]]\+/ /g" ) ")</code>\n"
        fi


    	done

    fi

}
function MessageAddHostSWRaidInfo () {
    if [[ ! $(ls /dev | grep md) == "" ]]; then
    	Message="$Message\n<b>Состояние MD рейдов</b>"
    	Message="$Message\n<code>$(cat /proc/mdstat | grep md)</code>\n"
    fi

    Message="$Message\n<b>Состояние ZFS пулов</b>"

    condition=$(/sbin/zpool status | grep -E -i '(DEGRADED|FAULTED|OFFLINE|UNAVAIL|REMOVED|FAIL|DESTROYED|corrupt|cannot|unrecover)')
    if [ "${condition}" ]; then
      Message="$Message - <b>Ошибка</b>"
      problems=1
    fi

    maxCapacity=80
    capacity=$(/sbin/zpool list -H -o capacity)
    for line in ${capacity//%/}
    do
      if [ $line -ge $maxCapacity ]; then
        Message="$Message - Нехватка свободного места"
        warnings=1
      fi
    done

    errors=$(/sbin/zpool status | grep ONLINE | grep -v state | awk '{print $3 $4 $5}' | grep -v 000)
    if [ "${errors}" ]; then
      Message="$Message - Неисправность диска(ов)"
      problems=1
    fi
     DAYS=30
#     LANG=C
     NOW=$(date +%s)
     POOLS=$(zpool list -H -o name)
     for pool in "$POOLS"
     do
       Message="$Message\n <code>$pool:</code>"
       ZPOOLSTATUS=$(/sbin/zpool status $pool)
       if [ $(echo "$ZPOOLSTATUS" | egrep -c "none requested") -ge 1 ]; then
         warnings=1
         Message="$Message 🚧 Ошибка SCRUB: Необходимо вручную в первый раз запустить \"zpool scrub $pool\"."
         continue
       fi
       if [ $(echo "$ZPOOLSTATUS" | egrep -c "scrub in progress|resilver") -ge 1 ]; then
         Message="$Message SCRUB уже в процессе."
         continue
       fi
#
#       # Get last time
       POOLLASTSCRUB=$(echo "$ZPOOLSTATUS" | grep "scan:" | grep "scrub" | rev | cut -f1-5 -d ' ' | rev)
       if [[ ! -z  $POOLLASTSCRUB ]]; then
         #       # convert scrub date to unix time
         LASTSCRUB=$(date -d"$POOLLASTSCRUB" +%s)
  #       # Add N days to last time
         NEXTSCRUB=$(date -d "$(date -d @$LASTSCRUB)+$DAYS days" +"%s")
  #
  #       # compare current time
         if [ "$NOW" -ge "$NEXTSCRUB" ]; then
           Message="$Message Запуск SCRUB."
           /sbin/zpool scrub $pool
         else
           Message="$Message SCRUB запланирован на $(date -d @$NEXTSCRUB "+%d-%m-%Y")."
         fi
       fi

     done

}
function MessageSend () {
  echo $Message"\n"
  if [ "$problems" -ne 0 ]; then
  	telegram-notify --icon 1F525 --html --title "$DISPLAY_TITLE" --text "<b>Общее состояние:🚨 Критическое!!!</b>\n\n$Message \n\n\n <code>$(zpool status)</code>"
  	logger $Message
  elif [ "$warnings" -ne 0 ]; then
    telegram-notify --icon 26A1 --html --title "$DISPLAY_TITLE" --text "<b>Общее состояние:🚧 Предупреждение!</b>\n\n$Message \n\n\n <code>$(zpool status)</code>"
    logger $Message
  else
  	telegram-notify --success --html --title "$DISPLAY_TITLE" --silent --text "<b>Общее состояние:✅ Все нормально.</b>\n\n$Message \n\n\n <code>$(zpool list)</code>"
  fi
}

while test $# -gt 0
do
  case "$1" in
#    "--text") shift; DISPLAY_TEXT="$1"; shift; ;;
#    "--photo") shift; PICTURE="$1"; shift; ;;
#    "--document") shift; DOCUMENT="$1"; shift; ;;
    "--title") shift; DISPLAY_TITLE="$1"; shift; ;;
#    "--html") DISPLAY_MODE="html"; shift; ;;
#    "--silent") DISPLAY_SILENT="true"; shift; ;;
#    "--config") shift; FILE_CONF="$1"; shift; ;;
#    "--user") shift; USER_ID="$1"; shift; ;;
#    "--key") shift; API_KEY="$1"; shift; ;;
#    "--success") DISPLAY_ICON=$(echo -e "\U2705"); shift; ;;
#    "--warning") DISPLAY_ICON=$(echo -e "\U26A0"); shift; ;;
#    "--error") DISPLAY_ICON=$(echo -e "\U1F6A8"); shift; ;;
#    "--question") DISPLAY_ICON=$(echo -e "\U2753"); shift; ;;
#    "--icon") shift; DISPLAY_ICON=$(echo -e "\U$1"); shift; ;;
    *) shift; ;;
  esac
done

problems=0
warnings=0
Message=""
dpkg_dependencies=("nvme-cli" "curl" "net-tools")

checkinstalldependencies "${dpkg_dependencies[@]}"
checkinstalltelegramnotify
MessageAddHostInformation
MessageAddHostDiskInfo
MessageAddHostSWRaidInfo
MessageSend

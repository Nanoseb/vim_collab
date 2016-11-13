#!/bin/bash
# License WTFPL

if [ "$1" ]
then
  file="$1"
else
  file='defaultfile'
fi
file_temp=$file".temp"
file_temp_diff=$file".diff"
file_prevsrv=$file".prevsrv"

ftp="ftp://ftp.website.org/folder/$file"
user="USERNAME"
pass='PASSWORD'
dtime="5"
logfile="/dev/null"

tstamp_srv=$(date +%s)
tstamp_local=$(date +%s)
prev_head=""

send_file () {
  diff=$(diff $file_prevsrv $file)
  if [ "$diff" ]
  then
    echo SEND_FILE
    cp "$file" "$file_prevsrv" 
    tstamp_srv=$(date +%s)
    curl -s --ssl -T "$file" "$ftp" --user "$user":"$pass" 
  fi
}

get_file () {
  echo GET FILE 0
  head=$(curl -s -R --ssl -u "$user":"$pass" "$ftp" --head)
  if [ "$prev_head" != "$head" ]
  then
    echo GET_FILE
    curl -s -R --ssl -u "$user":"$pass" "$ftp" -o "$file_temp"
    prev_head="$head"
  fi
}

check_srv () {
  get_file
  diff=$(diff "$file_prevsrv" "$file_temp")
  if [ "$diff" ]
  then
    # file on ftp have been updated
    cp "$file_temp" "$file_prevsrv" 
    merge
  fi
}

merge () {
  echo MERGE
  tstamp_local=$(stat -c %Y "$file")

  if [ "$tstamp_local" -lt "$tstamp_srv" ]
  then
    echo MERGE 1
    # issue, merging needed

    # vim --servername "$file" --remote-send '<ESC>:w<CR>li'
    diff=$(diff -D "EDITED" "$file" "$file_temp" > "$file_temp_diff")
    cat $file_temp_diff
    bool=$(grep '#else /\* EDITED \*/' < "$file_temp_diff") 

    if [ "$bool" ]
    then
      echo MERGE 1.1
      cp "$file_temp_diff" "$file"
      vim --servername "$file" --remote-send '<ESC>:edit!<CR>li'
    else
      echo MERGE 1.2
      grep -v "^#.*EDITED" < "$file_temp_diff" > "$file"
      vim --servername "$file" --remote-send '<ESC>:edit!<CR>li'
    fi
    send_file 
  else
    echo MERGE 2
    # fine we can merge easily
    cp "$file_temp" "$file"
    vim --servername "$file" --remote-send '<ESC>:edit!<CR>li'
  fi
}


run () {
  vim --servername "$file" "$file" 
}

init () {
  head=$(curl -s -R --ssl -u "$user":"$pass" "$ftp" --head)
  if [ "$head" ]
  then
    get_file
    cp "$file_temp" "$file" 
    cp "$file_temp" "$file_prevsrv"
  else
    echo "NEW FILE" > "$file"
    touch "$file_prevsrv"
    send_file 
    cp "$file" "$file_temp"
    cp "$file" "$file_prevsrv"
  fi
}

loop () {
  while true;
  do
    sleep "$dtime"
    check_srv >> "$logfile" 2>&1
  done
}

init >> "$logfile" 2>&1
loop &
pid=$!
run
kill $pid  >> "$logfile" 2>&1
check_srv >> "$logfile" 2>&1

rm "$file_temp"
rm "$file_prevsrv" 
rm "$file_temp_diff"

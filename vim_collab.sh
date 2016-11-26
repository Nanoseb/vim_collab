#!/bin/bash
# License WTFPL

if [ "$1" ]
then
  file="$1"
else
  file='defaultfile'
fi
file_temp="$file.temp"
file_temp_diff="$file.diff"
file_prevsrv="$file.prevsrv"
servername="${file}_vimcollab_$(date +%s)"

ftp="ftp://ftp.website.org/folder/$file"
user="USERNAME"
pass='PASSWORD'
dtime="2"
logfile="/dev/null"
md2html='true'

tstamp_srv=$(date +%s)
tstamp_local=$(date +%s)
prev_head=""

send_file () {
  diff=$(diff $file_prevsrv $file)
  if [ "$diff" ]
  then
    echo SEND_FILE
    cp "$file" "$file_prevsrv" 
    curl -s --ssl -T "$file" "$ftp" --user "$user":"$pass" 
    prev_head=$(curl -s -R --ssl -u "$user":"$pass" "$ftp" --head)

    if [ "$md2html" = "true" ]
    then
      echo MD2HTML
      pandoc --from markdown_github --to html --standalone "$file"  | \
        curl -s --ssl -T /dev/stdin "$ftp".html --user "$user":"$pass"
    fi
  fi
}


get_file () {
  echo GET_FILE_CHECK
  head=$(curl -s -R --ssl -u "$user":"$pass" "$ftp" --head)
  if [ "$prev_head" != "$head" ]
  then
    echo GET_FILE
    curl -s -R --ssl -u "$user":"$pass" "$ftp" -o "$file_temp"
    cp "$file_temp" "$file_prevsrv" 
    tstamp_srvprev=$tstamp_srv
    tstamp_srv=$(date +%s)
    prev_head="$head"
    return 0
  else
    return 1
  fi
}


check_srv () {
  if get_file
  then
    # file on ftp has been updated
    merge
  else
    send_file 
  fi
}


merge () {
  echo MERGE
  tstamp_local=$(stat -c %Y "$file")

  if [ "$tstamp_local" -lt "$tstamp_srv" ] && [ "$tstamp_srvprev" -lt "$tstamp_local" ]
  then
    echo MERGE 1
    # issue, merging needed
    #vim --servername "$servername" --remote-send '<ESC>:w<CR>li'
    diff=$(diff -D "EDITED" "$file" "$file_temp" > "$file_temp_diff")

    bool=$(grep '#else /\* EDITED \*/' < "$file_temp_diff") 
    if [ "$bool" ]
    then
      echo MERGE 1.1
      cp "$file_temp_diff" "$file"
      vim --servername "$servername" --remote-send '<ESC>:edit!<CR>li'
    else
      echo MERGE 1.2
      grep -v "^#.*EDITED" < "$file_temp_diff" > "$file"
      vim --servername "$servername" --remote-send '<ESC>:edit!<CR>li'
    fi
    send_file 
  else
    echo MERGE 2
    # fine we can merge easily
    cp "$file_temp" "$file"
    vim --servername "$servername" --remote-send '<ESC>:edit!<CR>li'
  fi
}


run () {
  vim --servername "$servername" "$file" 
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

rm "$file_temp"  >> "$logfile" 2>&1
rm "$file_prevsrv"  >> "$logfile" 2>&1
rm -f "$file_temp_diff" >> "$logfile" 2>&1
rm "$file" >> "$logfile" 2>&1


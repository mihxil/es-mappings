#!/usr/bin/env bash

if [ "$DEBUG" = "true" ] ; then
    set -x
fi

if [ $# -lt 1 ];
then
    echo "Usage $0 <es-url> [<index number>|<alias>]"
    echo "index number:  Number of the new index to create (e.g. 2 in apimedia-2). If omitted the mappings are put over the old ones (only possible if they are compatible)"
    echo "Each index has 2 aliases: apimedia (read) apimedia-publish (write)."
    echo "This script will create a new index and point the publisher to it."
    echo "You will have to manually move the apimedia after you copied the index"
    exit
fi

desthost=$1

basedir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
echo $basedir
needssettings=false
if [ "$2" == "" ] ; then
    echo "No index number found, trying to put mappings over existing ones (supposing they are compatible)"
    destindex=apimedia
else
    if [[ $2 =~ ^[0-9]+$ ]] ; then
        if (( $2 > 0 )) ; then
            previndex=apimedia-$(($2-1))
        fi
        destindex=apimedia-$2
        needssettings=true
    else
        echo "No index number found, trying to put mappings over existing ones (supposing they are compatible)"
        destindex=$2
    fi
    echo "$previndex -> $destindex"

fi

echo "Echo putting $basedir to $desthost/$destindex"

declare -a arr=( "group" "program" "segment" "deletedprogram" "deletedgroup" "deletedsegment" "cue" "programMemberRef" "groupMemberRef" "segmentMemberRef" "episodeRef" )
rm $destindex.json
echo '{' > $destindex.json
if [ "$needssettings" = true ]; then
    echo "putting settings"
    echo '"settings":' >> $destindex.json
    cat $basedir/setting/apimedia.json >> $destindex.json
    echo "," >> $destindex.json

    echo '"mappings": {' >> $destindex.json


    for i in "${!arr[@]}"
    do
        mapping=${arr[$i]}
        if [ $i -gt 0 ]; then
            echo "," >> $destindex.json
        fi
        echo '"'$mapping'": ' >>  $destindex.json
        cat $basedir/mapping/$mapping.json >> $destindex.json
    done
    echo -e '}\n}' >> $destindex.json

    echo Created $destindex.json
    curl -XPUT -H'content-type: application/json' $desthost/$destindex -d@$destindex.json
else
    echo "previndex $previndex . No settings necessary"
    for i in "${!arr[@]}"
    do
        mapping=${arr[$i]}
        echo curl -XPUT -H'content-type: application/json' $desthost/$destindex/$mapping/_mapping -d@$basedir/mapping/$mapping.json
        curl -XPUT -H'content-type: application/json' $desthost/$destindex/$mapping/_mapping -d@$basedir/mapping/$mapping.json
    done
fi


if [ "$previndex" != "" ] ; then

   echo "moving alias $previndex $destindex"

   publishalias="{
        \"actions\": [
            { \"remove\": {
                \"alias\": \"apimedia-publish\",
                \"index\": \"$previndex\"
            }},
            { \"add\": {
                \"alias\": \"apimedia-publish\",
                \"index\": \"$destindex\"
            }}
        ]
      }"
   echo $publishalias
   echo
   curl -XPOST $desthost/_aliases -d "$publishalias"
   echo

# Copy index
  echo
  echo "WARNING: You should execute this command to copy old to new index"
  echo "Execute this command:"
  reindex="{
    \"source\": {
      \"index\": \"$previndex\"
      },
     \"dest\": {
      \"index\": \"$destindex\"
      }
     }"

  echo curl -XPOST $desthost/_reindex -d "'$reindex'"
#End copy index

#Start move apimedia (read) alias
  echo
  echo "WARNING: See command before! Once the index is copied you can move the alias."
  echo "Execute this command:"
   alias="{
    \"actions\": [
            { \"remove\": {
                \"alias\": \"apimedia\",
                \"index\": \"$previndex\"
            }},
            { \"add\": {
                \"alias\": \"apimedia\",
                \"index\": \"$destindex\"
            }}
        ]
    }"
   echo curl -XPOST $desthost/_aliases -d "'$alias'"

#End move apimedia

fi

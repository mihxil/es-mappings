#!/usr/bin/env bash

if [ "$DEBUG" = "true" ] ; then
    set -x
fi

commandline_args=("$@")


function _init() {
    basename=$1
    if [ ${#commandline_args[@]} -lt 1 ];
    then
        echo "Usage $0 <es-url> [<index number>|<alias>]"
        echo "index number:  Number of the new index to create (e.g. 2 in $basename-2). If omitted the mappings are put over the old ones (only possible if they are compatible)"
        echo "Each index has 2 aliases: $basename (read) $basenamea-publish (write)."
        echo "This script will create a new index and point the publisher to it."
        echo "You will have to manually move the apimedia after you copied the index"
        exit
    fi
    desthost=${commandline_args[0]}
    number=${commandline_args[1]}

    echo "basename $basename"
    needssettings=false
    if [ "$number" == "" ] ; then
        echo "No index number found, trying to put mappings over existing ones (supposing they are compatible)"
        destindex=$basename
    else
        if [[ $number =~ ^[0-9]+$ ]] ; then
            if (( $number > 0 )) ; then
                seq=$(($number-1))
                previndex="$basename-$seq"
            fi
            destindex="$basename-$number"
            needssettings=true
        else
            echo "No index number found, trying to put mappings over existing ones (supposing they are compatible)"
            destindex=$number
        fi
        echo "$previndex -> $destindex"

    fi



}

function put() {
    basedir=$1
    shift
    _init $1
    shift
    echo "Echo putting $basedir to $desthost/$destindex"
    local arr=("$@")
    rm $destindex.json
    echo '{' > $destindex.json
    if [ "$needssettings" = true ]; then
        echo "putting settings"
        echo '"settings":' >> $destindex.json
        settingfile=$basedir/setting/$basename.json
        if [ ! -e $settingfile ] ; then
           echo "Setting file $settingfile doesn't exist"
           exit
        fi
        cat $basedir/setting/$basename.json >> $destindex.json
        echo "," >> $destindex.json
        echo '"mappings": {' >> $destindex.json

        for i in "${!arr[@]}"
        do
            mapping=${arr[$i]}
            echo $mapping
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

    if [ "$number" == "" ] ; then
        echo "Updating existing index. No aliases, not reindexing needed"
    else
        echo "For number $number"
        exit
        ## Now aliases
        publishalias='{"actions": ['
        if [ $number -gt 0 ] ; then
            # updating an index. Remove the exsting publish alias
            # remove publish alias
            publishalias="$publishalias
        {
         \"remove\": {
           \"alias': \"$basename-publish\",
           \"index\": \"$previndex\"
         }},"
        else
            # completely new index. Create also an api alias
            publishalias="$publishalias
        {

            \"add\": {
              \"alias\": \"$basename\",
              \"index\": \"$destindex\"
         }},"
        fi
        # Create a publish alias for the new index in any case
        publishalias="$publishalias
  {

            \"add\": {
              \"alias\": \"$basename-publish\",
              \"index\": \"$destindex\"
         }}]}"
        echo $publishalias
        curl -XPOST -H'content-type: application/json'  $desthost/_aliases -d "$publishalias"

        reindex="{
        \"source\": { \"index\": \"$previndex\" },
        \"dest\": { \"index\": \"$destindex\" }
     }"

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
                \"alias\": \"$basename\",
                \"index\": \"$previndex\"
            }},
            { \"add\": {
                \"alias\": \"$basename\",
                \"index\": \"$destindex\"
            }}
        ]
    }"
        echo curl -XPOST $desthost/_aliases -d "'$alias'"
   fi




}

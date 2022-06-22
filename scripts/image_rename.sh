#!/bin/bash
usage() {
    echo "Usage: $(basename $0) [OPTIONS] <path>"
    echo "Renames media files uploaded to Nextcloud according to creation date."
    echo
    echo "  -u  Nextcloud user, optional and case sensitive"
    echo "  -p  Nextcloud relative path, necessary for occ files:scan to work"
    echo "  -m  mode, one of either \"single\" or \"batch\" (BATCH NOT IMPLEMENTED YET), defaults to \"single\""
    echo "  -o  operation, one of either \"cp\" or \"mv\", defaults to \"cp\""
    echo "  <path> must be a path to a file in single mode or a directory in batch mode"
    echo
    echo "If -u is provided, the script will not rename files unless there is a file named"
    echo ".rename_<nextcloud-user> file in the base directory of <path>, which can optionally contain"
    echo "SUBFOLDER_YEAR=1 and SUBFOLDER_MONTH=1 to move renamed files into year/month/ subfolders."
}

# function to echo to stderr
echoerr() { echo "ERROR: $@" 1>&2; }

# TODO - maybe split these up, allow only image or video processing.
if [ ! -e /usr/bin/identify ] || [ ! -e /usr/bin/ffprobe ]; then
    echoerr "imagemagick and ffmpeg need to be installed."
    exit 1
fi

######
### Parse arguments
######

NC_USER=
REL_PATH=
MODE="single"
OPER="cp"
IN_PATH=

while getopts "u: p: m: o:" option; do
    case "$option" in
        u ) # user
            NC_USER="$OPTARG";;
        p ) # relative path, used by Nextcloud's occ files:scan
            REL_PATH="$OPTARG";;
        m ) # mode
            MODE="$(echo "$OPTARG" | tr [:upper:] [:lower:])";;
        o ) # operation
            OPER="$OPTARG"
    esac
done

shift $((OPTIND-1))
IN_PATH="$1"

case $MODE in
    "single" ) # single file mode
        if [ ! -f "$IN_PATH" ]; then
            echoerr "$IN_PATH must be a file."; usage; exit 1
        fi
        IN_FILENAME=$(basename "$IN_PATH")
        OUT_BASE=$(dirname "$IN_PATH")
        # sed to correct relative paths for group folders, which is incorrectly reported by Workflow Script app as of v1.7.0
        OUT_REL_BASE=$(dirname "$REL_PATH" | sed 's/__groupfolders\/[0-9]*\///')
        IN_REL_BASE="$OUT_REL_BASE"
        OUT_SUBFOLDERS=
        ;;
    # TODO - implement batch mode. For now, do a something like find . -iname="*.jpg" -exec image_rename.sh {} \;
    * )
        usage; exit 1
        ;;
esac

if [ "$OPER" != "cp" ] && [ "$OPER" != "mv" ]; then
    echoerr "operation must be one of cp or mv"
    exit 1
fi

echo "##### Input file $IN_PATH #####"

######
### If Nextcloud user provided, get relevant info
######

if [ ! -z "$NC_USER" ]; then
    SUBFOLDER_NAME=
    SUBFOLDER_YEAR=
    SUBFOLDER_MONTH=
    if [ ! -f "$OUT_BASE/.rename_$NC_USER" ]; then
        # not an error, we just do not want to rename these files
        # TODO - maybe remove the echo or make a verbose option
        echo "the Nextcloud user $NC_USER has not configured renaming files in the folder $OUT_BASE"
        exit 0
    else
        SUBFOLDER_NAME="$(grep SUBFOLDER_NAME $OUT_BASE/.rename_$NC_USER | cut -d "=" -f 2)"
        if [ ! -z "$SUBFOLDER_NAME" ]; then
            if [ "$SUBFOLDER_NAME" = "1" ]; then
                OUT_SUBFOLDERS="$NC_USER"
                # OUT_BASE="$OUT_BASE/$NC_USER"
                # OUT_REL_BASE="$OUT_REL_BASE/$NC_USER"
            else
                # use whatever value they want, but sanitize it
                SUBFOLDER_NAME="$(echo "$SUBFOLDER_NAME" | tr -dc [:alnum:])"
                OUT_SUBFOLDERS="$SUBFOLDER_NAME"
                # OUT_BASE="$OUT_BASE/$SUBFOLDER_NAME"
                # OUT_REL_BASE="$OUT_REL_BASE/$SUBFOLDER_NAME"
            fi
        fi
        # grab these, but wait to process until we have the file's date
        SUBFOLDER_YEAR="$(grep SUBFOLDER_YEAR $OUT_BASE/.rename_$NC_USER | cut -d "=" -f 2)"
        SUBFOLDER_MONTH="$(grep SUBFOLDER_MONTH $OUT_BASE/.rename_$NC_USER | cut -d "=" -f 2 | tr [:upper:] [:lower:])"
    fi
fi

#######
### Determine filetype and get the date accordingly
#######

# removes everything before and including the last "." and makes it lowercase
EXT=$(echo ${IN_FILENAME/*./} | tr [:upper:] [:lower:])

# extensions supported, separated into two types
EXIF_EXTENSIONS="@(jpg|jpeg|tiff)"
VID_EXTENSIONS="@(mp4)"
OTHER_EXTENSIONS="@(gif|bmp|png)"
shopt -s extglob

DATE=
MODEL=
case $EXT in
    $EXIF_EXTENSIONS )
        echo "image filetype detected"

        # get as much exif data as we can in a single call to identify, since it's a big slow command
        EXIF_PARTS=$(identify -format "%[exif:DateTime]|%[exif:SubSecTime]|%[exif:OffsetTime]|%[exif:Model]" "$IN_PATH")

        DATE=$(echo "$EXIF_PARTS" | cut -d "|" -f 1)
        # get the camera model, remove any unwanted characters
        MODEL=$(echo "$EXIF_PARTS" | cut -d "|" -f 4 | tr -d "()\r\f\n" | tr -sc "[:alnum:]" "_")

        if [ ! -z "$DATE" ]; then
            # change "yyyy:mm:dd" to "yyy-mm-dd" so the date can be understood
            DATE=$(echo "$DATE" | sed "s/^\([0-9]\{4\}\):\([0-9]\{2\}\):/\1-\2-/")
            SUBSEC=$(echo "$EXIF_PARTS" | cut -d "|" -f 2)
            OFFSET=$(echo "$EXIF_PARTS" | cut -d "|" -f 3)

            if [ ! -z "$SUBSEC" ]; then
                DATE=$DATE".$SUBSEC"
            fi

            if [ ! -z "$OFFSET" ]; then
                DATE=$DATE" $OFFSET"
            fi
        else
            echo "nooo can't find picture creation date metadata, will use stat of file"
            # using modification time, since it seems more reliable than file birth
            DATE=$(stat -c %y "$IN_PATH")
        fi
        ;;

    $VID_EXTENSIONS )
        echo "video filetype detected"

        DATE=$(ffprobe -v quiet -select_streams v:0 -show_entries stream_tags=creation_time -of default=noprint_wrappers=1:nokey=1 "$IN_PATH")
        if [ -z $DATE ]; then
            echo "nooo can't find movie creation date metadata, will use stat of file"
            # using modification time, since it seems more reliable than file birth
            DATE="$(stat -c %y "$IN_PATH")"
        fi
        ;;

    $OTHER_EXTENSIONS )
        echo "other filetype detected"

        # using modification time, since it seems more reliable than file birth
        DATE=$(stat -c %y "$IN_PATH")
        ;;

    * )
        echoerr "unsupported filetype"
        exit 1
        ;;
esac

FILENAME=$(date --utc --date="$DATE" +%Y.%m.%d_%H.%M.%S.%3N)
# check exit status, this is an important one, don't want to continue with a bad filename.
if [ "$?" != "0" ]; then
    echoerr "Could not get date!"
    exit 1
fi

if [ ! -z "$MODEL" ]; then
    FILENAME=$FILENAME"-$MODEL"
fi

######
### Determine if Nextcloud user wants year/month|quarter subfolders
######

if [ ! -z "$NC_USER" ] && [ "$SUBFOLDER_YEAR" = "1" ]; then
    OUT_SUBFOLDERS="$OUT_SUBFOLDERS/$(date --utc --date="$DATE" +%Y)"

    if [ ! -z "$SUBFOLDER_MONTH" ]; then
        MONTH="$(date --utc --date="$DATE" +%m)"

        case "$SUBFOLDER_MONTH" in
            "1"|"month"|"monthly")
                OUT_SUBFOLDERS="$OUT_SUBFOLDERS/$MONTH" ;;
            "quarter"|"quarterly")
                # remove leading zero if present
                MONTH="$(echo $MONTH | sed 's/^0//')"
                # integer division ftw
                OUT_SUBFOLDERS="$OUT_SUBFOLDERS/Q$(( ($MONTH + 2) / 3 ))"
                ;;
        esac
    fi
fi

# add subfolders, squash repeated slashes, and remove trailing slashes
OUT_BASE="$(echo "$OUT_BASE/$OUT_SUBFOLDERS" | tr -s "/" "/" | sed 's/\/*$//')"
OUT_REL_BASE="$(echo "$OUT_REL_BASE/$OUT_SUBFOLDERS" | tr -s "/" "/" | sed 's/\/*$//')"

OUT_FULLPATH="$OUT_BASE/$FILENAME.$EXT"
OUT_REL_FULLPATH="$OUT_REL_BASE/$FILENAME.$EXT"

# if file exists, add a three digit "alphabetic number" like ABC to the end. This will allow for 17,576 unique values.
if [ -e  "$OUT_FULLPATH" ]; then
    # TODO - check md5sum, if it's the same then just ignore it
    # TODO - make this more efficient maybe? Probably not often that I'll have hundreds of files with *identical* creation/modified dates, but...
    COUNTER=0
    SUFFIX=AAA
    while [ -e "$OUT_BASE/$FILENAME-$SUFFIX.$EXT" ]; do
        # terminate if we literally have 17,576 files with the same datetime...
        if [ SUFFIX = "ZZZ" ]; then
            echoerr "Could not make a unique filename!"
            exit 1
        fi

        let "COUNTER++"
        # bc can convert numbers from any input base to any output base
        # example in my use case: the output is "01 00" for input of 26
        NUMBER=$(echo "obase=26; ibase=10; $COUNTER" | bc)
        # make sure NUMBER has three "words," add zero padding on the left if necessary
        while [ $(echo "$NUMBER" | wc -w) -lt 3 ]; do NUMBER="00 "$NUMBER; done
        # using %c to print the ascii table characters for a given number, using number + 65 since A = 65
        SUFFIX=$(echo "$NUMBER" | awk '{ printf "%c%c%c", $1+65, $2+65, $3+65 }')
    done

    OUT_FULLPATH="$OUT_BASE/$FILENAME-$SUFFIX.$EXT"
    OUT_REL_FULLPATH="$OUT_REL_BASE/$FILENAME-$SUFFIX.$EXT"
fi

echo "##### Output file $OUT_FULLPATH #####"

# DO IT!
mkdir -p "$OUT_BASE"
if [ "$OPER" = "cp" ]; then
    cp --preserve=all "$IN_PATH" "$OUT_FULLPATH"
elif [ "$OPER" = mv ]; then
    mv "$IN_PATH" "$OUT_FULLPATH"
else
    echoerr "Strange... That should have worked."
    exit 1
fi

if [ "$IN_REL_BASE" != "." ]; then
    php /var/www/html/occ files:scan --path="$OUT_REL_FULLPATH"
    # scan the original base folder to detect the absence of original file
    # Note that this might be slow if there are many other files in this base
    php /var/www/html/occ files:scan --path="$IN_REL_BASE" --shallow
fi

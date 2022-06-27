#!/bin/bash
# Author: Richard McWhirter (Qenupve)
# Original date: 2022-02-06

usage() {
cat <<EOF
Usage: $(basename $0) [OPTION]... FILEPATH
Renames media files according to creation datetime in UTC, with optional
integration with Nextcloud via the Workflow Scripts app.

  -u  (Nextcloud) user, optional and case sensitive. If provided, subfolder
      settings must be provided as well.
  -p  Nextcloud relative path, optional but necessary if using Nextcloud for
      occ files:scan to work.
  -m  mode, one of either "single" or "batch" (BATCH NOT IMPLEMENTED YET),
      defaults to "single".
  -o  operation, one of either "cp" or "mv", defaults to "cp".
  -s  subfolder settings, comma separated. Use -H for a list of settings.
      example: -s SUBFOLDER_NAME=1,SUBFOLDER_YEAR=1
  -h  print this usage info.
  -H  print this and additional subfolder settings info.
  FILE must be a path to a file in single mode or a directory in batch mode.
EOF
}

more_usage() {
cat <<EOF
If -u is provided, the script will not rename files unless there is either a
file named .rename_USER in the base directory of FILEPATH or if -s is
provided. The dotfile (if there is one) will be ignored if -s is provided. The
dotfile can be empty, in which case the file(s) will be renamed but not moved
into subfolders. Settings in dotfile must be on separate lines.

Subfolder settings: (format OPTION={allowed values})
  SUBFOLDER_PATH={case sensitive}
      **** If provided, all other subfolder options are ignored ****
      Freeform relative path of subfolder to move photos into. Placeholders
      NAME, YEAR, QUARTER, and MONTH will be replaced with the corresponding
      values based on -u and file datetime. Any characters that are not
      alphanumeric or any of ./()_- are removed. A (very bad, but valid)
      example:
        SUBFOLDER_PATH=../photos/QUARTER/apple/the_YEAR/NAME/MONTH/derp
      Result for -u Alice and input file date of June 30th 2022:
        ../photos/Q2/apple/the_2022/Alice/06/derp
  SUBFOLDER_NAME={1|case sensitive}
      If equals 1, subfolder path will start with NAME provided with -u. If any
      non-empty STRING is provided, subfolder path will start with
      CLEAN_STRING, where CLEAN_STRING removes all non alphanumeric chars.
  SUBFOLDER_YEAR={1}
      If equals 1, subfolder path will include YEAR, like 2022. If other
      subfolders are provided, YEAR will appear after NAME and before MONTH or
      QUARTER.
  SUBFOLDER_MONTH={1|case insensitive}
      If equals 1, m, month, or monthly, subfolder path will include MONTH
      after YEAR, like 05. If equals q, quarter, or quarterly, subfolder
      path will include QUARTER after YEAR, like Q2. This option
      enables SUBFOLDER_YEAR even if it is not specified.
EOF
}

# function to echo to stderr
echoerr() { echo "ERROR: $@" >&2; }

# TODO (Qenupve) - maybe split these up, allow only image or video processing.
if [ ! -e /usr/bin/identify ] || [ ! -e /usr/bin/ffprobe ]; then
    echoerr "imagemagick and ffmpeg need to be installed."
    exit 1
fi

######
### Initialize and parse arguments
######

NC_USER=
REL_PATH=
OUT_REL_BASE=
IN_REL_BASE=
MODE="single"
OPER="cp"
IN_PATH=

OUT_SUBFOLDERS=
SUBFOLDER_OPTS=
DOTFILE=
SUBFOLDER_PATH=
SUBFOLDER_NAME=
SUBFOLDER_YEAR=
SUBFOLDER_MONTH=

while getopts "hH u: p: m: o: s:" option; do
    case "$option" in
        h ) # help
            usage; exit 0 ;;
        H ) # extended help
            usage; more_usage; exit 0 ;;
        u ) # user
            NC_USER="$OPTARG";;
        p ) # relative path, used by Nextcloud's occ files:scan
            REL_PATH="$OPTARG";;
        m ) # mode
            MODE="$(echo "$OPTARG" | tr [:upper:] [:lower:])";;
        o ) # operation
            OPER="$OPTARG" ;;
        s ) # subfolder options
            # TODO (Qenupve) - rectify with dotfile
            SUBFOLDER_OPTS=1
            SUBFOLDER_PATH="$(echo $OPTARG | egrep -o "SUBFOLDER_PATH=[^,]*" | cut -d "=" -f 2 | tr -dc "[:alnum:]./()_\-")"
            SUBFOLDER_NAME="$(echo $OPTARG | egrep -o "SUBFOLDER_NAME=[^,]*" | cut -d "=" -f 2)"
            SUBFOLDER_YEAR="$(echo $OPTARG | egrep -o "SUBFOLDER_YEAR=[^,]*" | cut -d "=" -f 2)"
            SUBFOLDER_MONTH="$(echo $OPTARG | egrep -o "SUBFOLDER_MONTH=[^,]*" | cut -d "=" -f 2 | tr [:upper:] [:lower:])"
            ;;
    esac
done

shift $((OPTIND-1))
# tilde (~) doesn't work in double quotes, so replace it with the calling user's $HOME
IN_PATH="$(echo "$1" | sed "s#~#$HOME#")"

case $MODE in
    "single" ) # single file mode
        if [ ! -f "$IN_PATH" ]; then
            echoerr "$IN_PATH must be a file."; usage; exit 1
        fi
        IN_FILENAME=$(basename "$IN_PATH")
        OUT_BASE=$(dirname "$IN_PATH")
        if [ ! -z "$REL_PATH" ]; then
            # sed to correct relative paths for group folders, which is incorrectly reported by Workflow Script app as of v1.7.0
            OUT_REL_BASE=$(dirname "$REL_PATH" | sed 's/__groupfolders\/[0-9]*\///')
            IN_REL_BASE="$OUT_REL_BASE"
        fi
        ;;
    # TODO (Qenupve) - implement batch mode. For now, do a something like find . -iname="*.jpg" -exec image_rename.sh {} \;
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

# SUBFOLDER_OPTS trumps DOTFILE, but if NC_USER is set then we need at least one of them
if [ ! -z "$NC_USER" ] && [ "$SUBFOLDER_OPTS" != 1 ]; then
    if [ ! -f "$OUT_BASE/.rename_$NC_USER" ]; then
        # not necessarily an error, we just do not want to rename these files
        # TODO (Qenupve) - maybe remove the echo or make a verbose option
        echo "the Nextcloud user $NC_USER has not configured renaming files in the folder $OUT_BASE"
        exit 0
    else
        # TODO (Qenupve) - not sure I need DOTFILE
        # DOTFILE=1
        SUBFOLDER_PATH="$(grep SUBFOLDER_PATH $OUT_BASE/.rename_$NC_USER | cut -d "=" -f 2 | tr -dc "[:alnum:]./()_\-")"
        SUBFOLDER_NAME="$(grep SUBFOLDER_NAME $OUT_BASE/.rename_$NC_USER | cut -d "=" -f 2)"
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
### Determine subfolders
######

# initialize OUT_SUBFOLDERS with SUBFOLDER_NAME if present
if [ ! -z "$SUBFOLDER_NAME" ]; then
    if [ "$SUBFOLDER_NAME" = "1" ] && [ ! -z "$NC_USER" ]; then
        OUT_SUBFOLDERS="$NC_USER"
    else
        # use whatever value they want, but sanitize it
        SUBFOLDER_NAME="$(echo "$SUBFOLDER_NAME" | tr -dc [:alnum:])"
        OUT_SUBFOLDERS="$SUBFOLDER_NAME"
    fi
fi

if [ ! -z "$SUBFOLDER_PATH" ] || [ ! -z "$SUBFOLDER_YEAR" ] || [ ! -z "$SUBFOLDER_MONTH" ]; then
    YEAR="$(date --utc --date="$DATE" +%Y)"
    MONTH="$(date --utc --date="$DATE" +%m)"
    # remove leading zero if present
    QUARTER="$(echo $MONTH | sed 's/^0//')"
    # integer division ftw
    QUARTER="Q$(( ($QUARTER + 2) / 3 ))"
fi

if [ ! -z "$SUBFOLDER_PATH" ]; then
    # overwrite OUT_SUBFOLDERS; if SUBFOLDER_NAME was provided, it is no longer part of OUT_SUBFOLDERS
    OUT_SUBFOLDERS="$(echo $SUBFOLDER_PATH | sed "s/NAME/$NC_USER/; s/YEAR/$YEAR/; s/MONTH/$MONTH/; s/QUARTER/$QUARTER/")"
else
    case "$SUBFOLDER_MONTH" in
        "1"|"month"|"monthly")
            OUT_SUBFOLDERS="$OUT_SUBFOLDERS/$YEAR/$MONTH" ;;
        "q"|"quarter"|"quarterly")
            OUT_SUBFOLDERS="$OUT_SUBFOLDERS/$YEAR/$QUARTER" ;;
        "" ) # no month/quarter, but check if we want year
            if [ "$SUBFOLDER_YEAR" = "1" ]; then
                OUT_SUBFOLDERS="$OUT_SUBFOLDERS/$YEAR"
            fi
            ;;
    esac
fi

# add subfolders, include leadingd / so the relative base looks absolute, which Nextcloud needs for occ files:scan
OUT_BASE="$(realpath -m "$OUT_BASE/$OUT_SUBFOLDERS")"
OUT_REL_BASE="$(realpath -m "/$OUT_REL_BASE/$OUT_SUBFOLDERS")"

OUT_FULLPATH="$OUT_BASE/$FILENAME.$EXT"
OUT_REL_FULLPATH="$OUT_REL_BASE/$FILENAME.$EXT"

# if file exists, add a three digit "alphabetic number" like ABC to the end. This will allow for 17,576 unique values.
if [ -e  "$OUT_FULLPATH" ]; then
    IN_SHA="$(sha1sum "$IN_PATH" | cut -d " " -f 1)"
    OUT_SHA="$(sha1sum "$OUT_FULLPATH" | cut -d " " -f 1)"
    
    if [ "$OUT_SHA" != "$IN_SHA" ]; then
        # TODO (Qenupve) - make this more efficient with binary search tree?
        # Probably not often that I'll have hundreds of files with *identical* creation/modified dates, but it's slow when there are...
        COUNTER=0
        SUFFIX="AAA"
        while [ -e "$OUT_BASE/$FILENAME-$SUFFIX.$EXT" ] && [ "$OUT_SHA" != "$IN_SHA" ]; do
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

            # calculate the sha1, if the file doesn't exist that's fine, OUT_SHA be empty but we'll still exit the loop
            OUT_SHA="$(sha1sum "$OUT_BASE/$FILENAME-$SUFFIX.$EXT" | cut -d " " -f 1)"
        done

        OUT_FULLPATH="$OUT_BASE/$FILENAME-$SUFFIX.$EXT"
        OUT_REL_FULLPATH="$OUT_REL_BASE/$FILENAME-$SUFFIX.$EXT"
    fi

    if [ "$OUT_SHA" = "$IN_SHA" ]; then
        echo "output already exists and the hashes match"
        if [ "$OPER" = "mv" ] && [ "$IN_BASE" != "$OUT_BASE" ]; then
            rm "$IN_PATH"
        fi
        exit 0
    fi
fi

echo "##### Output file $OUT_FULLPATH #####"

# DO IT!
mkdir -p "$OUT_BASE"
if [ "$?" = 0 ]; then
    if [ "$OPER" = "cp" ]; then
        cp --preserve=all "$IN_PATH" "$OUT_FULLPATH"
    elif [ "$OPER" = "mv" ]; then
        mv "$IN_PATH" "$OUT_FULLPATH"
    fi

    if [ ! -z "$IN_REL_BASE" ]; then
        php /var/www/html/occ files:scan --path="$OUT_REL_FULLPATH"
        # scan the original base folder to detect the absence of original file
        # Note that this might be slow if there are many other files in this base
        php /var/www/html/occ files:scan --path="$IN_REL_BASE" --shallow
    fi
else
    echoerr "could not create output directory!"
    exit 1
fi
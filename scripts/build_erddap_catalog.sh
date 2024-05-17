#! /bin/bash --

. ~/.bashrc;

PATH=${PATH}:/bin:${HOME}/code;

app=$(basename $0);

the_host='titanic-new';
# Change $erddap_server to point to the appropriate ERDDAP server
erddap_server='slocum-test';
#datasets_xml_file="/opt/tds/servers/${erddap_server}/content/erddap/datasets.xml";
#datasets_xml_tmp_file="/opt/tds/servers/${erddap_server}/content/erddap/datasets.xml.tmp";
content_root="/storage/apps/${erddap_server}/tomcat/content/erddap";
datasets_xml_file="${content_root}/datasets.xml";
datasets_xml_tmp_file="${content_root}/datasets.xml.tmp";

# Default values for options

# Usage message
USAGE="
NAME
    $app - 

SYNOPSIS
    $app [hx]

DESCRIPTION

    NOTICE: This script can only be run on ${the_host}.

    Create the ERDDAP datasets.xml file containing RU-COOL glider data sets. The datasets.xml catalog
    can be found at:

        $datasets_xml_file 

    -h
        show help message

    -x
        debug mode. No file operations performed.

";

# Process options
while getopts "hx" option
do
    case "$option" in
        "h")
            echo -e "$USAGE";
            exit 0;
            ;;
        "x")
            debug=1;
            ;;
        "?")
            echo -e "$USAGE" >&2;
            exit 1;
            ;;
    esac
done

# Remove option from $@
shift $((OPTIND-1));

. logging.sh;
[ "$?" -ne 0 ] && exit 1;

host=$(hostname -s);
if [ "$host" != "${the_host}" ]
then
    error_msg "This script may only be run on ${the_host} (Current host is ${host}).";
    exit 1;
fi

# Make sure $content_root exists and is accessible
if [ ! -d "$content_root" ]
then
    error_msg "Cannot access ERDDAP content root: $content_root";
    exit 1;
fi

# Validate environment
if [ -z "$GLIDER_DATA_HOME" ]
then
    error_msg "\$GLIDER_DATA_HOME is not set to a valid location";
    exit 1;
elif [ ! -d "$GLIDER_DATA_HOME" ]
then
    error_msg "\$GLIDER_DATA_HOME is an invalid location: $GLIDER_DATA_HOME";
    exit 1;
fi

# Create and validate the ERDDAP xml directory
xml_dir="${GLIDER_DATA_HOME}/erddap-xml";
if [ ! -d "$xml_dir" ]
then
    error_msg "Invalid ERDDAP XML location: $xml_dir";
    exit 1;
fi

# Make sure we have deployment <dataset /> xml files to concatenate
info_msg "Checking for dataset XML files in: $xml_dir";
xml_file_count=$(find $xml_dir -mindepth 1 -maxdepth 1 -name '*erddap.xml' | wc -l);
info_msg "Found ${xml_file_count} dataset XML files";
[ "$xml_file_count" -eq 0 ] && exit 1;

# Validate the files used to make up datasets.xml
header_xml="${xml_dir}/header.xml";
footer_xml="${xml_dir}/footer.xml";

info_msg "Glider xml location: $xml_dir";
info_msg "datasets.xml       : $datasets_xml_file";
info_msg "datasets.xml.tmp   : $datasets_xml_tmp_file";
info_msg "Header file        : $header_xml";
info_msg "Footer file        : $footer_xml";

if [ ! -f "$header_xml" ]
then
    error_msg "Invalid datasets.xml header file: $header_file";
    exit 1;
fi

if [ ! -f "$footer_xml" ]
then
    error_msg "Invalid datasets.xml footer file: $footer_file";
    exit 1;
fi

if [ ! -f "$datasets_xml_file" ]
then
    error_msg "Invalid datasets.xml file: $datasets_xml_file";
    exit 1;
fi

if [ -f "$datasets_xml_tmp_file" ]
then
    info_msg "Deleting exising datasets.xml temporary file: $datasets_xml_tmp_file";
    rm $datasets_xml_tmp_file;
    [ "$?" -ne 0 ] && exit 1;
fi

if [ -n "$debug" ]
then
    debug_msg "$xml_file_count glider data set <dataset /> XML fragments to add";
    debug_msg "debug flag (-x) set. Skipping file operations";
    exit 0;
fi

# Create an empty datasets.xml.tmp file as group opendap_users
info_msg "Creating empty datasets.xml temp file: $datasets_xml_tmp_file";
sg opendap_users "touch $datasets_xml_tmp_file";
[ "$?" -ne 0 ] && exit 1;

# Add the header
info_msg 'Creating header...';
cat $header_xml > $datasets_xml_tmp_file;
if [ "$?" -ne 0 ]
then
    rm $datasts_xml_tmp_file;
    exit 1;
fi

# Add all <dataset /> xml files
info_msg "Adding $xml_file_count glider datasets...";
find $xml_dir -mindepth 1 -maxdepth 1 -name '*erddap.xml' -exec cat '{}' >> $datasets_xml_tmp_file \;
if [ "$?" -ne 0 ]
then
    rm $datasts_xml_tmp_file;
    exit 1;
fi

# Add the footer
info_msg 'Creating footer...';
cat $footer_xml >> $datasets_xml_tmp_file;
if [ "$?" -ne 0 ]
then
    rm $datasts_xml_tmp_file;
    exit 1;
fi

if [ ! -s "$datasets_xml_file" ]
then
    warn_msg "Deleting $datasets_xml_file is empty.":
    rm $datasts_xml_tmp_file;
    exit 1;
fi

# Update permissions
chmod 775 $datasets_xml_tmp_file;

# Move the temporary datasets.xml file to datasets.xml
info_msg "Moving $datasets_xml_tmp_file to $datasets_xml_file";
mv $datasets_xml_tmp_file $datasets_xml_file;

exit 0;


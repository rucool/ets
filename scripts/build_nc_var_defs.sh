#! /bin/bash --

PATH=${PATH}:/bin:${HOME}/code;

app=$(basename $0);

# Default values for options
default_fill_value=NaN;

# Usage message
USAGE="
NAME
    $app - extract names, data types and _FillValue from NetCDF files

SYNOPSIS
    $app [hs]

DESCRIPTION

    Extract the names, data types and _FillValue attributes from one or more NetCDF files. Print
    the results as a YAML array of dictionaries in which each list item is a dictionary describing
    the variable. Missing _FillValue attributes are replaced with the default value of $default_fill_value 
    unless operating in strict mode.

    -h
        Show help message
    
    -s
        Strict mode. Do not return records for which _FillValue is not defined

    -f FILL_VALUE
        Use FILL_VALUE as the default _FillValue if not found and not in strict (-s) mode

    -c
        Print csv records instead of YAML
";

# Process options
while getopts "hsf:c" option
do
    case "$option" in
        "h")
            echo -e "$USAGE";
            exit 0;
            ;;
        "s")
            strict_mode=1;
            ;;
        "f")
            default_fill_value="$OPTARG";
            ;;
        "c")
            to_csv=1;
            ;;
        "?")
            echo -e "$USAGE" >&2;
            exit 1;
            ;;
    esac
done

# Make sure ncdump is available
has_ncdump=$(which ncdump 2>/dev/null);
if [ "$?" -ne 0 ]
then
    error_msg 'Missing NetCDF ncdump utility';
    exit 1;
fi

# Remove option from $@
shift $((OPTIND-1));

. logging.sh;
[ "$?" -ne 0 ] && exit 1;

if [ "$#" -eq 0 ]
then
    error_msg 'No NetCDF files specified';
    exit 1;
fi

# Make the temporary file to store the ncdump -h output for each file
var_defs_file=$(mktemp "${TMPDIR}/${app}-var_defs-XXXXXX.tmp" 2>&1);
[ "$?" -ne 0 ] && error_msg "$var_defs_file" && exit 1;
info_msg "Created temporary NetCDF ncdump file $var_defs_file";
# Exit if the temporary file was not created
# Remove $tmpDir if SIG
trap "{ rm -Rf $var_defs_file; exit 255; }" SIGHUP SIGINT SIGKILL SIGTERM SIGSTOP;

#var_defs_file='./var_defs.tmp';
# Dump the NetCDF header as a CDL file, pull out the variable type definition, _FillValue and
# store in the temporary file
for nc in "$@"
do

    # Dump the NetCDF header as a CDL file into the temporary defs file
    ncdump -h $nc | grep -e $'^\t[a-z]' -e _FillValue  | sed 's/^\t*//g' >> $var_defs_file;

done

variables=$(grep -v '=' $var_defs_file | awk -F'(' '{print $1}' | sed 's/^\t*//g' | awk '{print $2}' | sort | uniq);

# Loop through each variable to find the data type and the _FillValue. If not in strict mode (-s) and
# no _FillValue is found for the variable, use $default_fill_value
for variable in $variables
do

    # Grab the variable datatype(s)
    dtype=$(grep $variable $var_defs_file | grep -v '=' | sed 's/(.*)//g' | grep -w $variable | awk '{print $1}' | sort | uniq);

    # If more than one datatype for a variable is found, warn and exit
    dtype_count=$(echo $dtype | wc -w);
    if [ "$dtype_count" -ne 1 ]
    then
        warn_msg "Multiple data types found for $variable";
        error_msg 'Aborting. A variable definition is restricted to a single data type';
        exit 1;
    fi

    # See if a _FillValue is assigned to the variable. If not in strict mode (-s) and no _FillValue is
    # found, use $default_fill_value instead
    fill_value=$(grep "^${variable}:_FillValue" $var_defs_file | awk -F" = " '{print $2}' | awk '{print $1}' | sort | uniq);
    fill_value_count=$(echo $fill_value | wc -w);
    if [ "$fill_value_count" -gt 1 ]
    then
        warn_msg "Multiple _FillValues found for $variable";
        error_msg 'Aborting. A variable definition is restricted to a single _FillValue';
        exit 1;
    fi

    if [ -z "$fill_value" ]
    then
        warn_msg "No _FillValue specified for variable $variable";
        if [ -z "$strict_mode" ]
        then
            warn_msg "Using default _FillValue: $default_fill_value";
            fill_value=$default_fill_value;
        else
            warn_msg "Skipping variable $variable with no _FillValue (-s, strict mode)";
            continue;
        fi
    fi

    if [ -n "$to_csv" ]
    then 
        echo "${variable},${dtype},${fill_value}";
    else
        echo -e "- name: ${variable}\n  dtype: ${dtype}\n  attrs:\n    _FillValue: ${fill_value}";
    fi

done

#info_msg "Removing variable definitions temporary file: $var_defs_file";
#rm $var_defs_file;


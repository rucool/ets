#! /bin/bash --

. ~/.bashrc;

PATH=${PATH}:/bin:${HOME}/code:${HOME}/code/db/slocum_gpt:${HOME}/code/ets/scripts;

app=$(basename $0);

# Usage message

# Default values for options
minutes=60;
mode='rt';
cdm_data_type='trajectory';
num_nc_files=0;

# USAGE {{{
USAGE="
NAME
    $app - Create an ERDDAP NetCDF variable definitions file

SYNOPSIS

    $app [hxc] [-d CDM_DATA_TYPE] [-m MODE] [-n INT] [DEPLOYMENT1..DEPLOYMENT2...]

DESCRIPTION

    $app [hxc] [-d CDM_DATA_TYPE] [-m MODE] [-n INT] [deployment1 deployment2 ...]

    Inspect 1 or more NetCDF files and create an ERDDAP variable definitions file used to generate the
    dataset's <dataset /> XML snippet. Active deployments are processed if no deployments are specified.

    -h
        show help message

    -d DATATYPE
        Specify cdm_data_type (trajectory or profile) [Default=$cdm_data_type]

    -m MODE
        Specify MODE (delayed or rt)

    -n INT
        Create the NetCDDF ERDDAP variable definitions file from the last ${num_nc_files} NetCDF files.
        If not specified, all NetCDF files are inspected.

    -c
        clobber the existing NetCDF ERDDAP variable definitions file

    -x
        debug (No file I/O performed)
";
# }}}

# Process options
while getopts "hxd:n:cm:" option
do
    case "$option" in
        "h")
            echo -e "$USAGE";
            exit 0;
            ;;
        "d")
            cdm_data_type=$OPTARG;
            ;;
        "m")
            mode=$OPTARG;
            ;;
        "n")
            num_nc_files=$OPTARG;
            ;;
        "c")
            clobber=1;
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

# Validate mode
if [ "$mode" != 'rt' -a "$mode" != 'delayed' ]
then
    error_msg "Invalid mode: $mode";
    echo "$USAGE";
    exit 1;
fi
# Validate cdm_data_type
if [ "$cdm_data_type" != 'trajectory' -a "$cdm_data_type" != 'profile' ]
then
    error_msg "Invalid cdm_data_type: $cdm_data_type";
    echo "$USAGE";
    exit 1;
fi

# Process specified deployments or select all active deployments if none specified
deployments="$@";
if [ "$#" -lt 1 ]
then
    info_msg "No deployments specified. Selecting ALL active deployments for processing";
    deployments=$(select_active_deployment_names.sh);
    [ "$?" -ne 0 ] && exit 1;
else
    info_msg "Processing specified deployments";
fi

if [ -z "$deployments" ]
then
    warn_msg "No deployments selected for processing";
    exit 0;
fi

# Number of deployments for processing and list them
deployment_count=$(echo "${deployments}" | wc -w);
info_msg "$deployment_count deployments selected for processing";

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

# Create the deployments data root location
deployments_root="${GLIDER_DATA_HOME}/deployments";
if [ ! -d "$deployments_root" ]
then
    error_msg "Invalid deployments data root: $deployments_root";
    exit 1;
fi

info_msg "Deployments Root: $deployments_root";

for deployment in $deployments
do

    info_msg "Checking deployment $deployment for ERDDAP variable definition files";

    # Validate deployment
    is_valid=$(validate_deployment_name.sh $deployment);
    [ "$?" -ne 0 ] && error_msg "Invalid deployment: $deployment" && continue;

    deployment_date=$(echo $deployment | awk -F- '{print $2}');
    year="${deployment_date:0:4}";
    
    config_dir="${deployments_root}/${year}/${deployment}/config";
    info_msg "Configuration path: $config_dir";
    if [ ! -d "$config_dir" ]
    then
        error_msg "Configuration directory does not exist: $config_dir";
        continue;
    fi

done


exit 0;


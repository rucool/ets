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
        Create the NetCDDF ERDDAP variable definitions file from the first and last INT NetCDF files.
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

total_nc_files=$(( $num_nc_files + $num_nc_files ));
# Process each deployment
for deployment in $deployments
do

    d=$(validate_deployment_name.sh $deployment > /dev/null 2>&1);
    if [ "$?" -ne 0 ]
    then
        warn_msg "Invalid deployment specified: $deployment";
        continue;
    fi

    info_msg "Processing $deployment...":

    # Get the deployment year
    year=$(select_deployment_year.sh $deployment);
    [ "$?" -ne 0 ] && continue;

    # Create the path to the deployment data location
    d_path="${deployments_root}/${year}/${deployment}";
    if [ ! -d "$d_path" ]
    then
        warn_msg "Invalid deployment home: $d_path";
        continue;
    fi

    # NetCDF configuration path
    config_root="${d_path}/config";
    if [ "$cdm_data_type" == 'trajectory' ]
    then
        cdm='raw-trajectory';
    else
        cdm='sci-profile';
    fi
    config_path="${config_root}/${cdm}";
    if [ ! -d "$config_path" ]
    then
        error_msg "Configuration location does not exist: $config_path";
        continue;
    fi

    # Validate output NetCDF location
    nc_root="${d_path}/data/out/nc";
    if [ "$mode" == 'rt' ]
    then
        nc_path="${nc_root}/${cdm}/rt";
    else
        nc_path="${nc_root}/${cdm}/delayed";
    fi

    # Validate log file location
    logs_path="${d_path}/proc-logs";
    if [ ! -d "$logs_path" ]
    then
        info_msg "Creating log file location: $logs_path";
        mkdir -m 775 $logs_path;
        [ "$?" -ne 0 ] && continue;
    fi

    # ERDDAP variable definitions file
#    vars_file="${config_path}/${cdm}-env_vars.yml";
    vars_file="${config_path}/${cdm}-var_defs.yml";

    info_msg "Configuration path: $config_path";
    info_msg "NetCDF destination: $nc_path";
    info_msg "ERDDAP var defs   : $vars_file";

    # Search for the NetCDF variable definitions file create from ${HOME}/code/ets/scripts/build_nc_vars_def.sh
    build_new=0;
    if [ -f "${vars_file}" ]
    then
        info_msg "Found existing NetCDF ERDDAP variable definitions file";
        if [ -n "${clobber}" ]
        then
            info_msg "Clobbering existing NetCDF ERDDAP variable definitions file";
            build_new=1;
        else
            warn_msg "Using existing NetCDF ERDDAP variable definitions file";
            warn_msg "Use -c to clobber the existing ERDDAP variable definitions file: $vars_file";
        fi
    else
        info_msg "No NetCDF ERDDAP variable definitions file found";
        build_new=1;
    fi

    if [ "${build_new}" -eq 0 ]
    then
        info_msg "No new NetCDF ERDDAP variable defintions to create";
        continue;
    fi

    # See if there are any NetCDF files to inspect. Skip deployment if none are found
    nc_count=$(find $nc_path -mindepth 1 -maxdepth 1 -name '*.nc' | wc -l);
    info_msg "Found ${nc_count} NetCDF files for inspection";
    if [ "$nc_count" -eq 0 ]
    then
        warn_msg "Skipping NetCDF ERDDAP variable definitions (No files found for inspection";
        continue;
    fi

    if [ -n "$debug" ]
    then
        debug_msg "Skipping file operations (-x)";
        continue;
    fi

    if [ ${num_nc_files} -le 0 ]
    then
        info_msg "Creating new NetCDF ERDDAP variable definitions file from all NetCDF files";
        build_nc_var_defs.sh ${nc_path}/*.nc > $vars_file;
    else
        info_msg "Creating new NetCDF ERDDAP variable definitions file from the first and last ${num_nc_files} NetCDF files ($total_nc_files total)";
        first=$(find $nc_path -name '*.nc' | sort -V | head -${num_nc_files} | tr '\n' ' ');
        last=$(find $nc_path -name '*.nc' | sort -V | tail -${num_nc_files} | tr '\n' ' ');
        nc_files="${first} ${last}";
        build_nc_var_defs.sh ${nc_files} > $vars_file;
    fi

done

exit 0;


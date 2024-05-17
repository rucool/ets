#! /bin/bash --

. ~/.bashrc;

PATH=${PATH}:/bin:${HOME}/code:${HOME}/code/db/slocum_gpt:${HOME}/code/ets/scripts;

app=$(basename $0);

# Usage message

# Default values for options
minutes=60;
conda_env='gliders';
mode='rt';
cdm_data_type='trajectory';
num_nc_files=0;
xml_dir="${GLIDER_DATA_HOME}/erddap-xml";

# USAGE {{{
USAGE="
NAME
    $app - Create an ERDDAP NetCDF variable definitions file

SYNOPSIS

    $app [hxc] [-d CDM_DATA_TYPE] [-m MODE] [-e ENVIRONMENT] [deployment1 deployment2 ...]

DESCRIPTION

    $app [hxc] [-d CDM_DATA_TYPE] [-m MODE] [-e ENVIRONMENT] [deployment1 deployment2 ...]

    Inspect 1 or more NetCDF files and create an ERDDAP variable definitions file used to generate the
    dataset's <dataset /> XML snippet. All XML files are written to:

        $xml_dir

    provided it exists.

    -h
        show help message

    -d DATATYPE
        Specify cdm_data_type (trajectory or profile) [Default=$cdm_data_type]

    -m MODE
        Specify MODE (delayed or rt) [Default=$mode]

    -c
        clobber the existing ERDDAP xml file if it exists

    -e ENVIRONMENT_NAME
        conda environment to run under

    -x
        debug (No file I/O performed)
";
# }}}

# Process options
while getopts "hxd:cm:e:" option
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
        "c")
            clobber=1;
            ;;
        "e")
            conda_env=$OPTARG;
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

if [ ! -d "$xml_dir" ]
then
    error_msg "ERDDAP XML directory does not exist: $xml_dir";
    continue;
fi

# Make sure conda environment exists
env_exists=$(conda env list | grep $conda_env);
if [ -z "$env_exists" ]
then
    error_msg "Conda environment does not exist: $conda_env";
    exit 1;
fi

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

# Activate the conda environment
info_msg "Activing conda environment: $conda_env";
conda activate $conda_env;

[ "$?" -ne 0 ] && exit 1;

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
    level='sci';
    if [ "$cdm_data_type" == 'trajectory' ]
    then
        level='raw';
    fi

    # Create the cdm type
    cdm="${level}-${cdm_data_type}";

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

    # Create the xml file name
    xml_file="${xml_dir}/${deployment}-${cdm}-${mode}-erddap.xml";

    info_msg "Configuration path: $config_path";
    info_msg "NetCDF destination: $nc_path";
    info_msg "ERDDAP var defs   : $vars_file";
    info_msg "ERDDAP XML file   : $xml_file";

    # Search for the NetCDF variable definitions file create from ${HOME}/code/ets/scripts/build_nc_vars_def.sh
    if [ ! -f "${vars_file}" ]
    then
        warn_msg "No NetCDF ERDDAP variable definitions found: $vars_file";
        continue;
    fi

    # See if the xml_file exists
    if [ -f "$xml_file" ]
    then
        if [ -n "$clobber" ]
        then
            info_msg "Clobbering existing XML file: $xml_file";
        else
            info_msg "Skipping existing XML file: $xml_file";
            continue;
        fi
    fi

    if [ -n "$debug" ]
    then
        debug_msg "Skipping ERDDAP <datset /> XML for deployment $deployment";
        continue;
    fi

    info_msg "Creating ERDDAP <dataset /> XML for $deployment";

    build_deployment_dataset_xml.py -d $cdm_data_type --level $level --defs $vars_file $deployment > $xml_file;
    
done

info_msg "Deactivating conda environment $conda_env";
conda deactivate;

exit 0;


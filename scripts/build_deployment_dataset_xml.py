#!/usr/bin/env python

import logging
import sys
import argparse
import os
import yaml
import re
from jinja2 import Environment, FileSystemLoader
from ets.constants import REQUIRED_PROFILE_VARIABLES, REQUIRED_TRAJECTORY_VARIABLES
from pprint import pprint as pp


def main(args):
    """Create the ERDDAP <dataset /> XML element for the specified data set."""

    log_level = getattr(logging, args.loglevel.upper())
    log_format = '%(asctime)s%(module)s:%(levelname)s:%(message)s [line %(lineno)d]'
    logging.basicConfig(format=log_format, level=log_level)

    deployment = args.deployment
    mode = args.mode
    dtype = args.dtype
    processing_level = args.level
    reload_minutes = args.reload
    update_millis = args.update
    xml_template = args.template
    clobber = args.clobber
    debug = args.debug
    defs_file = args.var_defs_file

    # Make sure the XML template file exists
    if not os.path.isfile(xml_template):
        logging.error('Invalid XML template: {:}'.format(xml_template))
        return 1

    # Environment variable setting for deployment data sets root path
    deployments_root = os.getenv('GLIDER_DATA_HOME')
    if not deployments_root:
        logging.error('GLIDER_DATA_HOME environment variable not set')
        return 1

    deployments_root = os.path.join(deployments_root, 'deployments')
    if not os.path.isdir(deployments_root):
        logging.error('Invalid deployment data sets home: {:}'.format(deployments_root))
        return 1

    year_regex = re.compile(r'-(\d{4})')
    match = year_regex.search(deployment)
    year = None
    if match:
        year = match.groups()[0]

    deployment_home = os.path.join(deployments_root, year, deployment)
    if not os.path.isdir(deployment_home):
        logging.error('Invalid data set home: {:}'.format(deployment_home))
        return 1

    # If specified, use the variable definitions file, otherwise try to find it based on processing_level and
    # dtype
    if defs_file:
        logging.info('Using specified definitions file: {:}'.format(defs_file))
        if not os.path.isfile(defs_file):
            logging.error('Invalid variable definitions files specified: {:}'.format(defs_file))
    else:
        if not dtype:
            logging.error('No variable definitions files specified so dtype must be specified')
            return 1

        logging.info('Searching for ERDDAP variable definitions file')
        defs_file = os.path.join(deployment_home, 'config',
                                 '{:}-{:}-var_defs.yml'.format(processing_level, dtype))

    if not os.path.isfile(defs_file):
        logging.error('Invalid variable definitions file: {:}'.format(defs_file))
        return 1

    ioos_categories_file = os.path.realpath(os.path.join(os.path.dirname(__file__), '..', 'src', 'ioos_categories.yml'))
    if not os.path.isfile(ioos_categories_file):
        logging.error('Invalid IOOS categories file: {:}'.format(ioos_categories_file))
        return 1

    # Set up the templating environment
    template_path = os.path.dirname(xml_template)
    xml_file = os.path.basename(xml_template)
    environment = Environment(loader=FileSystemLoader(template_path), trim_blocks=True, lstrip_blocks=True)
    # Load the template
    xmlt = environment.get_template(xml_file)

    # NetCDF file locations
    nc_path = os.path.join(deployment_home,
                           'data',
                           'out',
                           'nc',
                           '{:}-{:}'.format(processing_level, dtype),
                           mode)

    var_defs = {}
    try:
        with open(defs_file, 'r') as fid:
            var_defs = yaml.safe_load(fid)

    except (OSError, ValueError, IOError) as e:
        logging.error('Error reading {:}: {:}'.format(defs_file, e))
        return 1

    cdm_data_type = None
    if dtype == 'trajectory':
        required_vars = REQUIRED_TRAJECTORY_VARIABLES
        cdm_data_type = 'Trajectory'
    else:
        required_vars = REQUIRED_PROFILE_VARIABLES
        cdm_data_type = 'TrajectoryProfile'

    nc_vars = [v['name'] for v in var_defs]
    missing_nc_vars = [v for v in required_vars if v not in nc_vars]
    if missing_nc_vars:
        logging.warning('Missing one or more required {:} variables'.format(cdm_data_type))
        for var in missing_nc_vars:
            logging.warning('Missing required variable {:}'.format(var))
        return 1

    # Create the data set ID
    dataset_id = '{:}-{:}-{:}-{:}'.format(deployment, processing_level, dtype.lower(), mode)

    logging.info('Data set location: {:}'.format(deployment_home))
    logging.info('XML template: {:}'.format(xml_template))
    logging.info('Variable definitions: {:}'.format(defs_file))
    logging.info('IOOS categories: {:}'.format(ioos_categories_file))
    logging.info('ERDDAP CDM data type: {:}'.format(cdm_data_type))
    if debug:
        return 0

    ioos_cats = {}
    try:
        with open(ioos_categories_file, 'r') as fid:
            ioos_cats = yaml.safe_load(fid)
    except (OSError, IOError, ValueError) as e:
        logging.error('Error loading IOOS categories file: {:} ({:})'.format(ioos_categories_file, e))

    if ioos_cats:
        for d in var_defs:
            if d['name'] not in ioos_cats:
                ioos_cat = 'Unknown'
            else:
                ioos_cat = ioos_cats[d['name']]

            d['attrs']['ioos_category'] = ioos_cat

    # Create ordered list of displayed variables
    instrument_vars = sorted([i['name'] for i in var_defs if i['name'].startswith('instrument_')])
    dataset_vars = [*required_vars, *instrument_vars]

    # Find the remaining variables and sort them
    missing_vars = sorted([v['name'] for v in var_defs if v['name'] not in dataset_vars])

    # Create the final list of variables in the order we want them
    dataset_vars = [*dataset_vars, *missing_vars]

    # Create the sorted list of variable definitions
    unsorted_vars = [v['name'] for v in var_defs]
    sorted_var_defs = [var_defs[unsorted_vars.index(dataset_var)] for dataset_var in dataset_vars]

    # Set the ERDDAP data set title
    dataset_title = deployment
    if mode == 'rt':
        dataset_title = '{:} Real Time'.format(dataset_title)
    else:
        dataset_title = '{:} Delayed Mode'.format(dataset_title)
    if processing_level == 'sci':
        dataset_title = '{:} Science'.format(dataset_title)
    else:
        dataset_title = '{:} Raw'.format(dataset_title)
    if cdm_data_type == 'TrajectoryProfile':
        dataset_title = '{:} Profiles'.format(dataset_title)
    else:
        dataset_title = '{:} Time Series'.format(dataset_title)

    # Set the ERDDAP make a graph default query
    default_graph_query = 'longitude,latitude,time&amp;.draw=markers&amp;.marker=6%7C3&amp;.color=0xFFFFFF&amp;' \
                          '.colorBar=Rainbow2%7C%7C%7C%7C%7C&amp;.bgColor=0xffccccff'
    if cdm_data_type == 'TrajectoryProfile':
        if processing_level == 'raw':
            default_graph_query = 'sci_water_temp,depth,time&amp;time&gt;=max(time)-1days&amp;' \
                                  'sci_water_temp!=NaN&amp;.draw=markers&amp;.marker=6%7C3&amp;.color=0xFFFFFF&amp;' \
                                  '.colorBar=Rainbow2%7C%7C%7C%7C%7C&amp;.bgColor=0xffccccff&amp;.yRange=%7C%7Cfalse'
        else:
            default_graph_query = 'temperature,depth,time&amp;time&gt;=max(time)-1days&amp;temperature!=NaN&amp;' \
                                  '.draw=markers&amp;.marker=6%7C3&amp;.color=0xFFFFFF&amp;' \
                                  '.colorBar=Rainbow2%7C%7C%7C%7C%7C&amp;.bgColor=0xffccccff&amp;.yRange=%7C%7Cfalse'

    dataset_config = {'dataset_id': dataset_id,
                      'active': True,
                      'file_dir': nc_path,
                      'title': dataset_title,
                      'default_graph_query': default_graph_query}

    logging.info('ERDDAP cdm_data_type: {:}'.format(cdm_data_type))

    xml_out = xmlt.render(dataset=dataset_config,
                          variables=sorted_var_defs,
                          cdm_data_type=cdm_data_type,
                          n_millis=update_millis,
                          n_minutes=reload_minutes)

    sys.stdout.write('{:}\n'.format(xml_out))


if __name__ == '__main__':
    arg_parser = argparse.ArgumentParser(description=main.__doc__,
                                         formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    arg_parser.add_argument('deployment',
                            help='Glider deployment name formatted as glider-YYYYmmddTHHMM')

    arg_parser.add_argument('-m', '--mode',
                            help='Deployment dataset status <Default=rt>',
                            choices=['rt', 'delayed'],
                            default='rt')

    arg_parser.add_argument('--defs',
                            dest='var_defs_file',
                            help='Variable definitions YAML file. If not specified, the -d, --cdm_data_type option '
                                 'must specify the cdm_data_type which will be used to search for the corresponding '
                                 'variable definitions file in the deployment data set home.',
                            type=str)

    arg_parser.add_argument('-d', '--dtype',
                            help='Dataset type',
                            choices=['trajectory', 'profile'],
                            default='trajectory')

    arg_parser.add_argument('--level',
                            help='Processing level',
                            type=str,
                            choices=['raw', 'sci'],
                            default='raw')

    arg_parser.add_argument('-r', '--reload',
                            help='Reload data set metadata and data every N minutes',
                            type=int,
                            default=86400)

    arg_parser.add_argument('-u', '--update',
                            help='Look for new data files every N milliseconds',
                            type=int,
                            default=-1)

    arg_parser.add_argument('-t', '--template',
                            help='Erddap <dataset /> template file',
                            default=os.path.realpath(
                                os.path.join(os.path.dirname(__file__), '..', 'templates', 'gliders', 'gliders.xml')))

    arg_parser.add_argument('-c', '--clobber',
                            help='Clobber existing NetCDF files if they exist',
                            action='store_true')

    arg_parser.add_argument('-x', '--debug',
                            help='Check configuration and create NetCDF file writer, but does not process any files',
                            action='store_true')

    arg_parser.add_argument('-l', '--loglevel',
                            help='Verbosity level',
                            type=str,
                            choices=['debug', 'info', 'warning', 'error', 'critical'],
                            default='info')

    parsed_args = arg_parser.parse_args()

#    print(parsed_args)
#    sys.exit(13)

    sys.exit(main(parsed_args))

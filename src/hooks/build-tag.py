#!/usr/bin/python

"""
Script used to compile and deploy a tagged configuration on a deployment server.
This script is intended to be called by SVN post-commit hook script.
"""

__version__ = "1.0.3"
__author__  = "Michel Jouvin <jouvin@lal.in2p3.fr>"


import sys
import os
import re
import shutil
from subprocess import *
import StringIO
import pysvn
import logging
import logging.handlers
import syslog
import socket
from optparse import OptionParser
import ConfigParser


# Initializations
this_script = os.path.abspath(sys.argv[0])
verbosity = 0
lock_created = False
client = None
logger = None
tag = None
java_root = '/usr/java'
lock_file = '/var/lock/quattor-deploy'
script_parent_dir = os.path.dirname(os.path.dirname(this_script))

config_file_default = '/etc/quattor-deploy.conf'
config_sections = { 'build-tag':'build-tag', 'scdb':'scdb' }
config_defaults = StringIO.StringIO("""
# Options commented out are configuration options available for which no 
# sensible default value can be defined.
[build-tag]
# If not starting with /, relative to directory specified by option svn_cache
ant_cmd: external/ant/bin/ant
# ant options (passed through env variable ANT_OPTS)
#ant_opts: -Xmx2048M
# ant stdout: allow to redirect ant output to a file for debugging purposes (default is PIPE)
# Default changed to a file because of problem in subprocess module if the 
# output is very large (Python 2.4) leading to the parent/child communication
# to hang.
ant_stdout: /tmp/ant-deploy-notify.log
#ant_stdout: PIPE
# ant target to do the deployment. Default should be appropriate.
ant_target: deploy.and.notify
# If not starting with /, relative to /usr/java.
java_version: latest
# If not starting with /, relative to parent of this directory script
svn_cache: svncache
# Number of retries for SVN switch to new tag in case of error
switch_retry_count: 1
# Verbosity level
verbose: 0

[scdb]
# URL associated with the repository root. Required parameter without default value.
#repository_url: http://svn.example.com/scdb
# Branch where to create SCDB deployment tags
# Keep consistent with quattor.build.properties if not using default values.
tags_branch: /tags
# Branch corresponding to SCDB trunk (only branch allowed to deploy)
# Keep consistent with quattor.build.properties if not using default values.
trunk_branch: /trunk
""")

def abort(msg):
    logger.error("build-tag.py script failed:\n%s" % (msg))
    if lock_created:
      try:
        os.remove(lock_file)
      except OSError, detail:
        if detail.errno != 2:
          warning('Failed to delete lock file (%s): %s' % (lock_file,detail))
    sys.exit(2)

def warning(msg):
    logger.warning(msg)

def debug(level,msg):
  if level <= verbosity:
    if level == 0:
      logger.info(msg)
    else:
      logger.debug(msg)

def check_pid(pid):        
    """ Check for the existence of a unix pid (signal 0 does nothing). """
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True

# Configure loggers and handlers

logging_source = 'build-tag'
logger = logging.getLogger(logging_source)
logger.setLevel(logging.DEBUG)

#fmt=logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fmt=logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")

syslog_handler = logging.handlers.SysLogHandler('/dev/log')
syslog_handler.setLevel(logging.WARNING)
logger.addHandler(syslog_handler)

# SVN requires the response to be valid XML.
terminal_handler = logging.StreamHandler()
terminal_handler.setLevel(logging.DEBUG)
terminal_handler.setFormatter(fmt)
logger.addHandler(terminal_handler)


parser = OptionParser()
parser.add_option('--config', dest='config_file', action='store', default=config_file_default, help='Name of the configuration file to use')
parser.add_option('-v', '--debug', '--verbose', dest='verbosity', action='count', default=0, help='Increase verbosity level for debugging (on stderr)')
parser.add_option('--version', dest='version', action='store_true', default=False, help='Display various information about this script')
options, args = parser.parse_args()

if options.version:
  debug (0,"Version %s written by %s" % (__version__,__author__))
  debug (0,__doc__)
  sys.exit(0)

if len(args) < 1:
  abort("tag to deploy must be specified")  
  
if options.verbosity:
  verbosity = options.verbosity

tag = args[0]


# Read configuration file.
# The file must exists as there is no sensible default value for several options.

config = ConfigParser.ConfigParser()
config.readfp(config_defaults)
try:
  config.readfp(open(options.config_file))
except IOError, (errno,errmsg):
  if errno == 2:
    abort(1,'Configuration file (%s) is missing.' % (options.config_file))
  else:
    abort('Error opening configuration file (%s): %s (errno=%s)' % (options.config_file,errmsg,errno))
if not config.has_section(config_sections['scdb']):
  abort('[%s] section is missing in configuration file (%s)' % (config_sections['scdb'],options.config_file))
  
# Use verbose option from config file only if it specified a greater level of verbosity
# that the one specified on the command line.
try:
  section = config_sections['build-tag']
  config_verbose = config.getint(section,'verbose')
except ValueError:
  abort("Invalid value specified for 'verbose' (section %): must be an integer >=0" % (section))
if config_verbose > verbosity:
  verbosity = config_verbose

# Get mandatory options without default values
try:
  # Section [scdb]
  section = config_sections['scdb']
  option_name = 'repository_url'
  repository_url = config.get(config_sections['scdb'],option_name)
except ConfigParser.NoOptionError:
  abort("Option %s (section %s) is required but not defined" % (option_name,section))
# Remove trailing / as a SVN doesn't like a // in the url
if re.search('/$',repository_url):
  repository_url = repository_url.rstrip('/')
  debug(1,"Trailing / stripped from 'repository_url'. New value: %s" % (repository_url))

# Get options with default values
try:
  # Section [scdb]
  section = config_sections['scdb']
  option_name = 'tags_branch'
  tags_branch = config.get(section,option_name)
  
  # Section [build-tag]
  section = config_sections['build-tag']
  option_name = 'ant_cmd'
  ant_cmd = config.get(section,option_name)
  option_name = 'ant_target'
  ant_target = config.get(section,option_name)
  option_name = 'java_version'
  java_version = config.get(section,option_name)
  option_name = 'svn_cache'
  svn_cache = config.get(section,option_name)
  option_name = 'switch_retry_count'
  switch_retry_count = config.getint(section,option_name)
  option_name = 'ant_stdout'
  ant_stdout_file = config.get(section,option_name)
except ValueError:
  abort("Option % (section %s) not defined: internal error (default value should exist)." % (option_name,section))

# Ensure the branch names start with a / and has no trailing / (some SVN versions don't like //)
if not re.match('/',tags_branch):
  tags_branch = '/' + tags_branch
  debug(1,"Leading / added to 'tags_branch'. New value: %s" % (tags_branch))
# Remove trailing / as a SVN doesn't like a // in the url
if re.search('/$',tags_branch):
  tags_branch = tags_branch.rstrip('/')
  debug(1,"Trailing / stripped from 'tags_branch'. New value: %s" % (tags_branch))

# Optional ant_opts
section = config_sections['build-tag']
try:
  option_name = 'ant_opts'
  ant_opts = config.get(section,option_name)
except:
  ant_opts = None
  
if not re.match('^/',java_version):
  java_version = java_root + '/' + java_version
  
if not re.match('^/',svn_cache):
  svn_cache = script_parent_dir + '/' + svn_cache
  

# Checks availability of required applications
# ant existence must be tested after the check out as it is part of SCDB.

if not os.path.exists(java_version):
  abort("Specified Java version (%s) does not exist. Use 'java_version' to specify another version" % (java_version))
  

# Ensure there is not another instance of the script already running.
# Unfortunatly, as there is no way to open a new lock file without cloberring, this is
# a 2-step operation with a very small race condition if another script instance is doing the
# same test between both steps. But this is probably not a real issue as svncache will be locked
# by one of the instance and the other one will fail.

already_running = True
try:
  lock_fd = open(lock_file,'r')
except IOError, detail:
  if detail.errno == 2:
    already_running = False
  else:
    abort('Failed to open lock file (%s): %s' % (lock_file,detail))
if already_running:
  pidstr = lock_fd.readline().rstrip()
  lock_fd.close()
  try:
    pid=int(pidstr)
  except ValueError, detail:
    abort("Lock file (%s) found but doesn't contain a valid pid (%s)" % (lock_file,pidstr))
  if check_pid(pid):
    abort("%s already running (pid=%d). Retry later..." % (this_script,pid))
try:
  lock_fd = open(lock_file,'w')
  lock_fd.write(str(os.getpid()))
  lock_fd.close()
except IOError, detail:
  abort('Failed to open lock file (%s): %s' % (lock_file,detail))

# Switch SVN cache to new tag

tag_url = repository_url + tags_branch + '/' + tag

debug(0, "Processing tag %s..." % (tag_url))
debug(0, "SVN cache: %s" % (svn_cache))

client = pysvn.Client()
client.exception_style = 0

# If svn_cache exists, check it is valid, else delete it.
if os.path.isdir(svn_cache) and os.access(svn_cache,os.W_OK):
  try:
    debug(1,'Checking %s is a valid SVN working copy' % (svn_cache))
    wc_info = client.info(svn_cache)
  except pysvn.ClientError, e:
    warning("%s is not a valid SVN working copy. Deleting and checking out again..." % (svn_cache))
    shutil.rmtree(svn_cache)

# If svn_cache doesn't exist, do a checkout
if not os.path.isdir(svn_cache):
  try:
    debug(0,"Checking out %s into %s" % (tag_url,svn_cache))
    client.checkout(path=svn_cache,url=tag_url)
  except pysvn.ClientError, e:
    debug(1,'Error during checkout of %s. Trying to continue' % tag_url)

# Switch to new tag.
# Do also after an initial checkout as it may allow to complete a failed check out.
# Retry switch in case of errors as specified by switch_retry_count
switch_failed = True
i = 1
while switch_failed and i <= switch_retry_count:
  if i > 1 and switch_failed:
    debug(1,'Switch to tag %s failed. Retrying (%d/%d)...' % (tag,i,switch_retry_count))
  else:
    debug(0,'Switching to tag %s (url=%s)' % (tag,tag_url))
  switch_failed = False
  try:
    client.switch(path=svn_cache,url=tag_url)
  except pysvn.ClientError, e:
    switch_failed = True
    last_errror = e
  i += 1
if switch_failed:
  abort('Failed to switch SVN cache to new tag: %s' % (e))


# Compile and deploy

if not re.match(ant_cmd,'^/'):
  ant_cmd = svn_cache + '/' + ant_cmd

if not os.path.exists(ant_cmd) or not os.access(ant_cmd,os.X_OK):
  abort("ant (%s) not found. Use option 'ant_cmd' to specify another location." % (ant_cmd))
  
deploy_cmd = [ ant_cmd ]
deploy_cmd.append(ant_target)

ant_env = {}
ant_env['JAVA_HOME'] = java_version
if ant_opts:
  debug(1,'Defining ANT_OPTS as "%s"' % (ant_opts))
  ant_env['ANT_OPTS'] = ant_opts

if ant_stdout_file == 'PIPE':
  ant_stdout = PIPE
else:
  # Unfortunatly flag 'r+' doesn't create the file if it doesn't exist. It is then
  # necessary to reopen the file for reading.
  ant_stdout = file(ant_stdout_file, 'w')

debug(0,"Executing command: '%s'" % (' '.join(deploy_cmd)))
try:
  proc = Popen(deploy_cmd, shell=False, cwd=svn_cache, env=ant_env, stdout=ant_stdout, stderr=STDOUT)
  retcode = proc.wait()
  output = proc.communicate()[0]
  if not ant_stdout == PIPE:
    # Do not send back ant output if redirected to a file as it can be very large and tends to  cause
    # problems with Python subprocess module.
    try:
      ant_stdout.close()
      #ant_stdout = file(ant_stdout_file, 'r')
      #output = ant_stdout.read()
      output = "See %s on %s" % (ant_stdout_file,socket.getfqdn())
    except:
      debug(1,'Error reading ant output file(%s)' % (ant_stdout_file))
  if retcode < 0:
      abort('ant command aborted by signal %d. Command output:\n%s' % (-retcode, output))
  elif retcode > 0:
      abort('Error during ant command (status=%d). Script output:\n%s' % (retcode,output))
  else:
      debug(1,'Tag %s deployed successfully. Script output:\n%s' % (tag,output))
except OSError, detail:
  abort('Failed to execute ant command: %s' % (detail))  


# Remove lock file

try:
  os.remove(lock_file)
except OSError, detail:
  if detail.errno != 2:
    warning('Failed to delete lock file (%s): %s' % (lock_file,detail))


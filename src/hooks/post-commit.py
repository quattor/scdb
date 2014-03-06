#!/usr/bin/python

"""
SVN POST-COMMIT HOOK

Arguments:
  [1] REPOS-PATH   (the path to this repository)
  [2] REV          (the number of the revision just committed)

This script uses pysvn API to SVN to access the SVN repository.
"""

__version__ = "1.0.3"
__author__  = "Michel Jouvin <jouvin@lal.in2p3.fr>"


import sys
import re
from subprocess import *
import shlex
import StringIO
import pysvn
import logging
import logging.handlers
import syslog
from optparse import OptionParser
import ConfigParser

# Initializations
verbosity = 0
logger = None
revision = None

config_file_default = '/etc/quattor-deploy.conf'
config_sections = { 'hook':'post-commit', 'scdb':'scdb', 'ssh':'ssh', 'sudo':'sudo' }
config_defaults = StringIO.StringIO("""
# Options commented out are configuration options available for which no 
# sensible default value can be defined.
[post-commit]
# Script launched by the script to actually do the deployment
deploy_script : /root/quattor/scripts/build-tag.py
# Name of the deployment server where to run the deploy_script. Used only with ssh.
# This can be a space-separated list (not yet implemented, see https://trac.lal.in2p3.fr/LCGQWG/ticket/46).
#deploy_server : quattorsrv.example.org
# Userid to use to run deploy_script
deploy_user : root
# notify_xxx are used to configure email notification in case of errors.
# If notif_from or notif_to is undefined, email notification is disabled
notif_mailer : localhost
#notif_from=Quattor Deployment <noreply@lal.in2p3.fr>
#notif_to=jouvin@lal.in2p3.fr
notif_subject_prefix : [Quattor-Deploy]
notif_subject : Failed to deploy revision %s of SCDB configuration
# Default should be appropriate. Set to false if your client doesn't handle properly returned output.
# When set to false, no message is printed on stdout, except if verbose is > 0.
report_error_to_svn: yes
# When false, ssh is used instead. This requires deploy_server to be defined too.
use_sudo : yes
# Log operations in /tmp/quattor-post-commit.log
verbose: 0

[ssh]
cmd: /usr/bin/ssh
options: -o PasswordAuthentication=no

[sudo]
cmd: /usr/bin/sudo
options: -H

[scdb]
# URL associated with the repository root
#repository_url: http://svn.example.com/scdb
# Branch where to create SCDB deployment tags
# Keep consistent with quattor.build.properties if not using default values.
tags_branch: /tags
# Branch corresponding to SCDB trunk (only branch allowed to deploy)
# Keep consistent with quattor.build.properties if not using default values.
trunk_branch: /trunk
""")

# The following handler optionally adds before the first message a set of XML tags and
# ensures the matching closing tags when the handler is closed (or when the
# application exits). It also takes care of removing < and >.
# A SVN post-commit answer must be valid XML plain text without tags (they are added by
# SVN layer). In particular < and > must be removed or escpaed.
# FIXME: escape rather than remove < and > (MJ 14/9/09)
class MyXMLStreamHandler(logging.StreamHandler):
  # List of xml tag to put around error text
  #handler_xml_tags = ['error','message']
  #handler_xml_tags = ['S:post-commit-err']
  handler_xml_tags = []
  handler_header_sent = False
  header = None
  trailer = None
      
  def emit(self,record):
    # Record must be copied not to affect other handlers...
    newrecord = record
    # Remove < and > in the message if any as they break the XML structure
    newrecord.msg = re.sub('<','',newrecord.msg)
    newrecord.msg = re.sub('>','',newrecord.msg)
    if not self.handler_header_sent:
      self.header = ''
      self.trailer = ''
      for tag in self.handler_xml_tags:
        self.header += '<%s>' % (tag)
        self.trailer = '</%s>%s' % (tag,self.trailer)
      self.handler_header_sent = True
      newrecord.msg = "%s\n%s" % (self.header,newrecord.msg)
    logging.StreamHandler.emit(self,newrecord)

  def close(self):
    if self.trailer:
      #print "Closing MyXMLStremHander (trailer=%s)" % (self.trailer)
      record = logging.LogRecord('',0,'',0,self.trailer,None,None)
      logging.StreamHandler.emit(self,record)
    # Note than StreamHandler.close() is inherited from Handlers and does nothing
    logging.StreamHandler.flush(self)

def abort(msg):
    logger.error("SVN post-commit script failed:\n%s" % (msg))
    sys.exit(2)

def debug(level,msg):
  if level <= verbosity:
    if level == 0:
      logger.info(msg)
    else:
      logger.debug(msg)


# Configure loggers and handlers

logging_source = 'quattor-post-commit'
logger = logging.getLogger(logging_source)
logger.setLevel(logging.DEBUG)

#fmt=logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fmt=logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
# Handler used to report to SVN must display only the message to allow proper XML formatting
svn_fmt=logging.Formatter("%(message)s")

syslog_handler = logging.handlers.SysLogHandler('/dev/log')
syslog_handler.setLevel(logging.WARNING)
logger.addHandler(syslog_handler)

logfile_handler = logging.handlers.RotatingFileHandler('/tmp/quattor-post-commit.log','a',100000,10)
logfile_handler.setLevel(logging.DEBUG)
logfile_handler.setFormatter(fmt)
logger.addHandler(logfile_handler)

# SVN requires the response to be valid XML.
svn_handler = MyXMLStreamHandler()
svn_handler.setLevel(logging.DEBUG)
svn_handler.setFormatter(svn_fmt)
logger.addHandler(svn_handler)


parser = OptionParser()
parser.add_option('--config', dest='config_file', action='store', default=config_file_default, help='Name of the configuration file to use')
parser.add_option('-v', '--debug', '--verbose', dest='verbosity', action='count', default=0, help='Increase verbosity level for debugging (on stderr)')
parser.add_option('--version', dest='version', action='store_true', default=False, help='Display various information about this script')
options, args = parser.parse_args()

if options.version:
  debug (0,"Version %s written by %s" % (__version__,__author__))
  debug (0,__doc__)
  sys.exit(0)

if len(args) < 2:
  abort("Insufficient argument provided (2 required)")  
  
if options.verbosity:
  verbosity = options.verbosity

revision = args[1]


# Read configuration file.
# The file must exists as there is no sensible default value for several options.

config = ConfigParser.ConfigParser()
config.readfp(config_defaults)
try:
  config.readfp(open(options.config_file))
except IOError, (errno,errmsg):
  if errno == 2:
    debug(1,'Configuration file (%s) is missing. Using default values.' % (options.config_file))
  else:
    abort('Error opening configuration file (%s): %s (errno=%s)' % (options.config_file,errmsg,errno))
if not config.has_section(config_sections['hook']):
  abort('[%s] section is missing in configuration file (%s)' % (config_sections['hook'],options.config_file))
  
try:
  section = config_sections['hook']
  report_error_on_stdout = config.getboolean(section,'report_error_to_svn')
except ValueError:
  abort("Invalid value specified for 'report_error_to_svn' (section %s) (must be yes or no)" % (section))

# Delete handler associated with stdout if report of error message has been disabled.
# Ignore this option if verbose is > 0.
if not report_error_on_stdout and verbosity == 0:
  logger.removeHandler(svn_handler)

# Use verbose option from config file only if it specified a greater level of verbosity
# that the one specified on the command line.
try:
  section = config_sections['hook']
  config_verbose = config.getint(config_sections['hook'],'verbose')
except ValueError:
  abort("Invalid value specified for 'verbose' (section %s) (must be an integer >=0)" % (section))
if config_verbose > verbosity:
  verbosity = config_verbose

init_mail_handler = True
try:
  section = config_sections['hook']
  notif_mailer = config.get(section,'notif_mailer')
  notif_from = config.get(section,'notif_from')
  notif_to = config.get(section,'notif_to')
  notif_subject_fmt = config.get(section,'notif_subject')
  notif_subject = notif_subject_fmt % (revision)
except (ConfigParser.NoSectionError,ConfigParser.NoOptionError):
  init_mail_handler = False

if init_mail_handler:
  mail_handler = logging.handlers.SMTPHandler(notif_mailer,notif_from,notif_to,notif_subject)
  mail_handler.setLevel(logging.ERROR)
  mail_handler.setFormatter(fmt)
  logger.addHandler(mail_handler)

# Get options with default values
try:
  # Section [hook]
  section = config_sections['hook']
  option_name = 'deploy_script'
  deploy_script = config.get(section,option_name)
  option_name = 'deploy_user'
  deploy_user = config.get(section,option_name)

  # Section [scdb]
  section = config_sections['scdb']
  option_name = 'tags_branch'
  tags_branch = config.get(section,option_name)
  option_name = 'trunk_branch'
  trunk_branch = config.get(section,option_name)
except ValueError:
  abort("Option % not defined (section %s): internal error (default value should exist)." % (option_name,section))

# Ensure the branch names start with a / and has no trailing / (some SVN versions don't like //)
if not re.match('/',trunk_branch):
  trunk_branch = '/' + trunk_branch
  debug(1,"Leading / added to 'trunk_branch'. New value: %s" % (trunk_branch))
# Remove trailing / as a SVN doesn't like a // in the url
if re.search('/$',trunk_branch):
  trunk_branch = trunk_branch.rstrip('/')
  debug(1,"Trailing / stripped from 'trunk_branch'. New value: %s" % (trunk_branch))

try:
  section = config_sections['hook']
  use_sudo = config.getboolean(section,'use_sudo')
except ValueError:
  abort("Invalid value specified for 'use_sudo' (section %s): must be yes or no" % (section))
  
if use_sudo:
  cnx_section = 'sudo'
else:
  cnx_section = 'ssh'
  try:
    section = config_sections['hook']
    deploy_server = config.get(config_sections['hook'],'deploy_server')
  except ConfigParser.NoOptionError:
    abort("Required option 'deploy_server' (section %s) missing in configuration file (%s)" % (section,options.config_file))

try:
  option_name = 'cmd'
  cnx_cmd = config.get(config_sections[cnx_section],option_name)
  option_name = 'options'
  cnx_cmd_opts = shlex.split(config.get(config_sections[cnx_section],option_name))
except ValueError:
  abort("Option %s not defined (section %s): internal error (default value should exist)." % (option_name,config_sections[cnx_section]))

    
# Ensure there is a protocol in repos_path. Else add file:.
# The protocol is absent when the script is called as a post commit hook.
# In this case the first parameter is the file path to the repository.


if re.match('^[a-z]+://',args[0]):
  repos_path = args[0]
else:
  debug(1,'No SVN protocol specified. Assuming file:')
  repos_path = 'file://' + args[0]
debug (1,'Executing post-commit script for repository %s revision %s' % (repos_path,revision))


# Initialize pysvn

client = pysvn.Client()
client.exception_style = 0


# Get log information for the revision just commited
try:
  log_msgs = client.log(repos_path, \
                        discover_changed_paths=True, \
                        revision_start=pysvn.Revision(pysvn.opt_revision_kind.number, revision), \
                        revision_end=pysvn.Revision(pysvn.opt_revision_kind.number, revision) \
                       )
except pysvn.ClientError, e:
  abort("Failed to retrieve log message for %s:%s\n%s" % (repos_path,revision,str(e)))
  sys.exit(3)

#for log in log_msgs:
#  print "Log: '%s', changed paths (%d):" % (log['message'],len(log['changed_paths']))
#  for path in log['changed_paths']:
#    print "    %s (action=%s, copyfrom_path=%s, copyfrom_rev=%s)" % (path['path'],path['action'],path['copyfrom_path'],path['copyfrom_revision'])


# Check if the commit is a SCDB tag. Else do nothing.
# Note that there is only one log message as we asked for only one revision.
# In case there is no log message, treat as something other than a tag
# deployment and do nothing.

if len(log_msgs) == 0:
  debug(1,'No log message returned for path %s revision %s' % (repos_path,revision))
  sys.exit(0)
log = log_msgs[0]
if log['message'] != 'ant tag':
  debug(1,"Not a SCDB tag (log message=%s)" % (log['message']))
  sys.exit(0)
elif len(log['changed_paths']) != 1:
  debug(1,"Not a SCDB tag (%d changed paths instead of 1)" % (len(log['changed_paths'])))
  sys.exit(0)
  
changed_path = log['changed_paths'][0]
matcher = re.match('^%s/(?P<tag>(?:[0-9\.\-]+/?)+)$' % (tags_branch),changed_path['path'])
if changed_path['action'] != 'A':
  debug(1,"Not a SCDB tag (action is %s instead of A)" % (changed_path['action']))
  sys.exit(0)
elif not changed_path['copyfrom_path'] or changed_path['copyfrom_path'] != trunk_branch:
  debug(1,"Not a SCDB tag (copyfrom_path is %s instead of %s)" % (changed_path['copyfrom_path'],trunk_branch))
  sys.exit(0)
elif not matcher:
  debug(1,"Not a SCDB tag (path %s is not a valid tag format)" % (changed_path['path']))
  sys.exit(0)

tag = matcher.group('tag')
debug(1,"Deploying tag %s" % (tag))


if use_sudo:
  cnx_dest = None
else:
  cnx_dest = deploy_user + '@' + deploy_server
deploy_cmd = [ cnx_cmd ]
if cnx_dest:
  deploy_cmd.append(cnx_dest)
deploy_cmd.extend(cnx_cmd_opts)
deploy_cmd.append(deploy_script)
deploy_cmd.append(tag)

debug(1,"Executing command: '%s'" % (' '.join(deploy_cmd)))
try:
  proc = Popen(deploy_cmd, shell=False, stdout=PIPE, stderr=STDOUT)
  retcode = proc.wait()
  output = proc.communicate()[0]
  if retcode < 0:
      abort('Deployment script aborted by signal %d. Command output:\n%s' % (-retcode, output))
  elif retcode > 0:
      abort('Error during deployment script (status=%d). Script output:\n%s' % (retcode,output))
  else:
      debug(1,'Tag %s deployed successfully. %s output:\n%s' % (tag,deploy_script,output))
except OSError, details:
  abort('Failed to execute deployment script (%s): %s' % (deploy_script,details))  

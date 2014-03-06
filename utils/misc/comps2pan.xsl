<?xml version="1.0" encoding="UTF-8"?>

<!--
**** Copyright (c) 2004 by Charles A. Loomis, Jr. and Le Centre National de
**** la Recherche Scientifique (CNRS).  All rights reserved.
****
**** The software was distributed with and is covered by the European
**** DataGrid License.  A copy of this license can be found in the included
**** LICENSE file.  This license can also be obtained from
**** http://www.eu-datagrid.org/license.
-->


<!--
****
**** This style sheet transforms a comps.xml file which defines
**** various installation groups for RedHat-like systems 
**** (e.g. Fedora, RHES) into a set of PAN templates for quattor.
****
**** To use this you must first generate an appropriate package 
**** dependency file using the rpmProvides.pl and rpmRequires.pl
**** scripts.  These in turn require access to a complete, 
**** consistent set of rpms for the OS for which you are building
**** the rpm lists. 
****
**** This stylesheet uses features from XSLT 2.0, so such an XSLT
**** processor is required.  Saxon was used in testing and is 
**** recommended.  To use Saxon do the following:
****
**** export CLASSPATH=<path to saxon>/saxon8.jar 
**** java -Xss1M net.sf.saxon.Transform /dis/trib/base/comps.xml src/util/miscs/comps2pan.xsl \
****                                                             depdb=<dep db file> \
****                                                             output-dir=</absolute/output/dir> \
****                                                             [pan-prefix=<template name prefix>] \
****                                                             [namespace=<template-namespace>] \
****                                                             [ignore.missing.rpm=<true|false>] \
****                                                             [ignore.duplicates=<true|false>] \
****                                                             [kernel.version.explicit=<true|false>] \
****                                                             [debug=<level>]
**** 
**** This will output one template in 'output dir' per rpm group in comps.xml.
**** 'output dir' MUST BE an absolute path. On Windows, it must have the
**** following format (\ must be replaced by /) : 
****        /drive:/dir/ect/ory
****
**** depdb parameter is the output file produced by rpmRequires.
****
**** pan-prefix specifies a prefix to add to group name when building template
**** names. By default, it is empty.
****
**** namespace parameter allows to assign templates to a specific PAN namespace. By
**** default, namespace is 'rpms'. To suppress namespace, use ' '. This namespace is
**** used in the template declaration and in include directives for required groups.
**** It MUST MATCH end of output directory.
****
**** ignore.missing.rpm instructs comps2pan to issue a warning if they are listed group members
**** that are missing, rather than exiting with an error. This is expected with x86_64
**** architectures.
****
**** kernel.version.explicit : if true, the actual version is used. When false (default),
**** actual version in kernel and kernel modules is replaced by KERNEL_VERSION_NUM variable.
****
**** debug parameter, if present, defines debug level. debug messages are quite verbose
**** and not intended for normal use. Especially if level is >= 2...
****
**** If you get run time error 'Too many nested template or function calls', try to
**** increase -Xss parameter. This is due to the high level of recursion of XSL templates
**** used in this stylesheet. This is a feature and not a bug...!!!
****
**** Saxon can be obtained from http://saxon.sourceforge.net/.  Make
**** sure to download an XSLT 2.0-compatible version (i.e. Saxon v7+).
****
**** NOTE: The DTD for the comps.xml format is not available, but is
**** listed as the DOCTYPE for the file.  If the XML parser tries to 
**** validate the file, it will fail.  In this case, simply comment-out
**** the DOCTYPE element in the comps.xml file.
****
-->

<xsl:stylesheet 
      version='2.0'
      xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
      xmlns:xsd='http://www.w3.org/2001/XMLSchema'>
      
  <xsl:output method="text" version="1.0" encoding="UTF-8" indent="yes"/>

  <!-- Global variable which defines the group prefix to use in the
       output file.  This is set for Scientific Linux but can be changed to 
       anything appropriate. -->
  <xsl:param name="pan-prefix"/>

  <!-- Global variable which defines the PAN namespace to use in the
       output file. By default no namespace is used. -->
  <xsl:param name="namespace">rpms</xsl:param>

  <!-- Global variable saying to continue if there is a missing RPM
       rather than existing with an error. False by default. -->
  <xsl:param name="ignore.missing.rpm">false</xsl:param>

  <!-- Global variable saying to continue if there is a dependency made of several
       RPMs. This is an abnormal condition resulting from something wrong in dependency
       DB. This option can be used to workaround the problem. False by default. -->
  <xsl:param name="ignore.duplicates">false</xsl:param>

  <!-- Global parameter indicating the kernel variants available (smp, largesmp...).
       as a regexp. Default for SL : smp|largesmp. Should be appropriate for other distros -->
  <xsl:param name="kernel.variants">smp|largesmp|hugemem|xenU</xsl:param>
       
  <!-- Global parameter indicating if kernel version must be substituted by
       KERNEL_VERSION_NUM in kernel and kernel modules (default is to substitute) -->
  <xsl:param name="kernel.version.explicit">false</xsl:param>
       
  <!-- Global parameter which is a string identifying the XML file
       containing the dependency information. -->
  <xsl:param name="depdb" select="'rpm-requires.txt'"/>
  <xsl:param name="depdbcontent" select="doc($depdb)"/>

  <!-- The complete path for the output templates.  This MUST be
       terminated with a slash! -->
  <xsl:param name="output-dir"/>

  <!-- Create the directory URL. -->
  <xsl:variable name="dir-url">
    <xsl:value-of select="concat('file:',$output-dir)"/>
    <xsl:if test="not(ends-with($output-dir,'/'))">
      <xsl:text>/</xsl:text>
    </xsl:if>
  </xsl:variable>
  
  <!-- Debugging flag : disabled by default.
       Activated for any value that is a number.
       Value is a debug level. When > 1, very verbose -->
  <xsl:param name="debug" select="'0'" />
  <xsl:variable name="debug-level" as="xsd:double">
    <xsl:choose>
      <xsl:when test="number($debug)">
        <xsl:value-of select="number($debug)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="number(0)"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>


<!--
****
**** Process the root node. 
****
--> 
  <xsl:template match="/*">

    <!-- Check namespace validity : must match end of output-dir -->
    <xsl:if test="not(matches($output-dir,concat($namespace,'/*$')))">
      <xsl:message terminate="yes">
        <xsl:text>ERROR : Inconsistency between PAN namespace and output directory.&#xa;</xsl:text>
        <xsl:text>        output-dir parameter must end with </xsl:text><xsl:value-of select="$namespace"/>
      </xsl:message>
    </xsl:if>

    <!-- Variable identifying main architecture of the distribution. -->
    <xsl:variable name="distrib-arch" select="$depdbcontent/*/arch/distrib"/>
    <xsl:if test="not($distrib-arch)">
      <xsl:message terminate="yes">
        <xsl:text>ERROR : Distribution archicture missing in </xsl:text><xsl:value-of select="$depdb"/>
      </xsl:message>
    </xsl:if>

    <!-- Variable identifying kernel architecture of the distribution.
         When several are available, only one is used in the dependency DB -->
    <xsl:variable name="kernel-arch" select="$depdbcontent/*/arch/kernel"/>
    <xsl:if test="not($kernel-arch)">
      <xsl:message terminate="yes">
        <xsl:text>ERROR : Kernel archicture missing in </xsl:text><xsl:value-of select="$depdb"/>
      </xsl:message>
    </xsl:if>

    <!-- Variable indicating if a compatible architecture
       exists and if template for compatibility mode should be built -->
    <xsl:variable name="compat-arch" select="$depdbcontent/*/arch/compat"/>
          
    <!-- Variable indicating kernel compatible architecture (used by glibc) -->
    <xsl:variable name="compat-kernel-arch" select="$depdbcontent/*/arch/compat-kernel"/>
          
    <!-- Variable indicating Java architecture (not necessarily the same as distribution)
         exists and if template for compatibility mode should be built -->
    <xsl:variable name="java-arch" select="$depdbcontent/*/arch/java"/>
          
    <!-- Create the default template. -->
    <xsl:call-template name="makeDefaultGroup">
      <xsl:with-param name="groups" select="group"/>
    </xsl:call-template>

    <!-- Collect all of the accessible groups
         This is done by going through the dependency
         chain, starting with group without dependencies. -->
    <xsl:variable name="grps" as="xsd:string*">
      <xsl:for-each select="group[not(grouplist)]">
        <xsl:call-template name="findGroupDependencies">
          <xsl:with-param name="groupNode" select="."/>
        </xsl:call-template>
      </xsl:for-each>
    </xsl:variable>

    <!-- Apply the group template for group with ID matching the token. -->
    <xsl:apply-templates select="/*/group[string(id) = $grps]">
      <xsl:with-param name="compat-arch" select="$compat-arch"/>
      <xsl:with-param name="compat-kernel-arch" select="$compat-kernel-arch"/>
      <xsl:with-param name="distrib-arch" select="$distrib-arch"/>
      <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
      <xsl:with-param name="java-arch" select="$java-arch"/>
    </xsl:apply-templates>

  </xsl:template>


<!--
****
**** Process each group node.  Top-level template.
****
**** Parameters:
****    distrib-arch: distribution architecture
****    compat-arch: compatible architecture for distribution architecture, if any
****    compat-kernel-arch : kernel compatible architecture (used by glic)
****    kernel-arch : kernel architecture for the distribution
****    java-arch : Java archictecture (sometimes different from distribution arch)
--> 
  <xsl:template match="group">
    <xsl:param name="compat-arch"/>
    <xsl:param name="compat-kernel-arch"/>
    <xsl:param name="distrib-arch"/>
    <xsl:param name="kernel-arch"/>
    <xsl:param name="java-arch"/>
    
    <xsl:variable name="id">
      <xsl:call-template name="lowerCase">
        <xsl:with-param name="str" select="string(id)"/>
      </xsl:call-template>
    </xsl:variable>

    <xsl:variable name="compat-group">
      <xsl:choose>
        <xsl:when test="biarchonly">
          <xsl:value-of select="biarchonly"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="false()"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:choose>
      <xsl:when test="($compat-group = false()) or $compat-arch">
        <xsl:variable name="gname">
          <xsl:value-of select="concat($pan-prefix,$id)"/>
        </xsl:variable>

        <xsl:result-document href="{$dir-url}{$gname}.tpl">
          <xsl:message>
            <xsl:value-of select="concat('WRITING: ',$dir-url,$gname,'.tpl')"/>
          </xsl:message>
          <xsl:call-template name="header">
            <xsl:with-param name="name" select="$gname"/>
            <xsl:with-param name="desc" select="description[not(@xml:lang)]"/>
          </xsl:call-template>

          <xsl:for-each select="grouplist/groupreq">
            <xsl:call-template name="writeGroupEntry">
              <xsl:with-param name="groupId" select="string(.)"/>
              <xsl:with-param name="groupEnabled" select="'true'"/>
            </xsl:call-template>
          </xsl:for-each>

          <xsl:text>&#xa;</xsl:text>

          <xsl:variable name="requiredGroups" as="element() *">
            <xsl:call-template name="getRequiredGroups">
              <xsl:with-param name="groupNode" select="."/>
              <xsl:with-param name="compat-group" select="$compat-group"/>
            </xsl:call-template>
          </xsl:variable>

          <xsl:if test="$debug-level > 0">
            <xsl:message>
              <xsl:text>(match=group) - Required groups for group </xsl:text>
              <xsl:value-of select="string(id)"/>
              <xsl:text> : </xsl:text>
              <xsl:for-each select="$requiredGroups">
                <xsl:value-of select="string(id)"/>
                <xsl:text>,</xsl:text>
              </xsl:for-each>
            </xsl:message>
          </xsl:if>

          <xsl:variable name="includedPkgsTmp" as="element() *">
            <xsl:call-template name="findGroupPkgs">
              <xsl:with-param name="groupList" select="$requiredGroups"/>
              <xsl:with-param name="compat-arch" select="$compat-arch"/>
              <xsl:with-param name="compat-kernel-arch" select="$compat-kernel-arch"/>
              <xsl:with-param name="distrib-arch" select="$distrib-arch"/>
              <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
              <xsl:with-param name="java-arch" select="$java-arch"/>
              <xsl:with-param name="compat-group" select="$compat-group"/>
            </xsl:call-template>
          </xsl:variable>

          <xsl:if test="$debug-level > 1">
            <xsl:message>
              <xsl:text>(match=group) - Packages (without their dependencies) from required groups : </xsl:text>
              <xsl:value-of select="count($includedPkgsTmp)"/>
              <xsl:text>&#xa;</xsl:text>
              <xsl:for-each select="$includedPkgsTmp">
                <xsl:sort select="string(id)"/>
                <xsl:text>    </xsl:text>
                <xsl:value-of select="string(./id)"/>
                <xsl:text> (arch=</xsl:text>
                <xsl:value-of select="string(./arch)"/>
                <xsl:text>)&#xa;</xsl:text>
              </xsl:for-each>
            </xsl:message>
          </xsl:if>
                    
          <xsl:variable name="includedPkgs" as="element() *">
            <xsl:call-template name="collectPkgDependencies">
              <xsl:with-param name="pkgList" select="$includedPkgsTmp"/>
            </xsl:call-template>
          </xsl:variable>

          <xsl:if test="$debug-level > 0">
            <xsl:message>
              <xsl:text>(match=group) - Packages with dependencies included from required groups : </xsl:text>
              <xsl:value-of select="count($includedPkgs)"/>
              <xsl:text>&#xa;</xsl:text>
              <xsl:for-each select="$includedPkgs">
                <xsl:sort select="string(id)"/>
                <xsl:text>    </xsl:text>
                <xsl:value-of select="string(./id)"/>
                <xsl:text> (arch=</xsl:text>
                <xsl:value-of select="string(./arch)"/>
                <xsl:text>)&#xa;</xsl:text>
              </xsl:for-each>
            </xsl:message>
          </xsl:if>
                    
          <xsl:variable name="thisGroupPkgs" as="element() *">
            <xsl:variable name="thisGroupPkgsTmp" as="element() *">
              <xsl:for-each select="packagelist/packagereq">
                <xsl:call-template name="findPkgEntry">
                  <xsl:with-param name="pkgName" select="string(.)"/>
                  <xsl:with-param name="compat-arch" select="$compat-arch"/>
                  <xsl:with-param name="compat-kernel-arch" select="$compat-kernel-arch"/>
                  <xsl:with-param name="distrib-arch" select="$distrib-arch"/>
                  <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
                  <xsl:with-param name="java-arch" select="$java-arch"/>
                  <xsl:with-param name="compat-group" select="$compat-group"/>
                </xsl:call-template>
              </xsl:for-each>
            </xsl:variable>
            <xsl:call-template name="collectPkgDependencies">
              <xsl:with-param name="pkgList" select="$thisGroupPkgsTmp"/>
              <xsl:with-param name="processedPkgs" select="$includedPkgs"/>
            </xsl:call-template>
          </xsl:variable>

          <xsl:if test="$debug-level > 0">
            <xsl:message>
              <xsl:text>(match=group) - Group </xsl:text>
              <xsl:value-of select="string(id)"/>
              <xsl:text> packages : </xsl:text>
              <xsl:value-of select="count($thisGroupPkgs)"/>
              <xsl:text>&#xa;</xsl:text>
              <xsl:for-each select="$thisGroupPkgs">
                <xsl:sort select="string(id)"/>
                <xsl:text>    </xsl:text>
                <xsl:value-of select="string(./id)"/>
                <xsl:text> (arch=</xsl:text>
                <xsl:value-of select="string(./arch)"/>
                <xsl:text>)&#xa;</xsl:text>
              </xsl:for-each>
            </xsl:message>
          </xsl:if>
                              
          <xsl:call-template name="writePkgEntries">
            <xsl:with-param name="pkgList" select="$thisGroupPkgs"/>
            <xsl:with-param name="compat-group" select="$compat-group"/>
            <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
          </xsl:call-template>

          <xsl:text>&#xa;</xsl:text>

        </xsl:result-document>
      </xsl:when>

      <!-- Skip compatibility group if no compatible architecture -->
      <xsl:otherwise>
        <xsl:message>
          <xsl:value-of select="concat('SKIPPING : group ',$id,' (no compatible architecture)')"/>
        </xsl:message>
      </xsl:otherwise>
    </xsl:choose>
    
  </xsl:template>


<!--
****
**** Function to get each group required groups.
**** The list of group returned has no duplicates.
****
**** Parameters:
****    groupNode: the group node to process
****    groupProcessed : groups already found
****    compat-group: true if this group defines packages for compatibible architecture support (e.g. i386 for x86_64)
****
--> 
  <xsl:template name="getRequiredGroups" as="element() *">
    <xsl:param name="groupNode" as="element()"/>
    <xsl:param name="groupProcessed" select="()" as="element() *" />
    <xsl:param name="compat-group" select="false()" />

    <xsl:if test="$debug-level > 1">
      <xsl:message>
        <xsl:text>getRequiredGroups - Processing group </xsl:text>
        <xsl:value-of select="$groupNode/id"/>
      </xsl:message>
    </xsl:if>
    
    <!-- Get current group required groups -->
    <xsl:variable name="requiredGroupsTmp" as="xsd:string*">
      <xsl:for-each select="$groupNode/grouplist/groupreq">
         <xsl:value-of select="string(.)"/>
      </xsl:for-each>
    </xsl:variable>

    <!-- If this is a compatibility group, be sure to add 'base'
         even if not explicitly specified (as for SL3/4 this is the case
         and thus there is no explicit include for this group) -->
    <xsl:variable name="requiredGroupNames" as="xsd:string*">
      <xsl:sequence select="$requiredGroupsTmp"/>
      <xsl:variable name="baseGroup" select="'base'"/>
      <xsl:choose>
        <xsl:when test="($compat-group = true()) or (index-of($requiredGroupsTmp,$baseGroup) = 0)">
          <xsl:sequence select="$baseGroup"/>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>
    
    <!-- Get group nodes corresponding to group names
         and check if they are already present -->
    <xsl:variable name="requiredGroups" as="element() *">
      <xsl:for-each select="/*/group[string(id) = $requiredGroupNames]">
        <xsl:choose>
          <xsl:when test="not(count(.|$groupProcessed) = count($groupProcessed))">
            <xsl:sequence select="."/>
            <xsl:if test="$debug-level > 1">
              <xsl:message>
              <xsl:text>getRequiredGroups - Group added : </xsl:text>
                <xsl:value-of select="string(id)"/>
              </xsl:message>
            </xsl:if>
          </xsl:when>
          <xsl:otherwise>
            <xsl:if test="$debug-level > 1">
              <xsl:message>
              <xsl:text>getRequiredGroups - Group already present : </xsl:text>
                <xsl:value-of select="string(id)"/>
              </xsl:message>
            </xsl:if>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
    </xsl:variable>

    <!-- Recursively process current group group requirements...
         compat-group is never true() for required groups
         (a compatibility group doesn't include another compatibility group) -->
    <xsl:if test="$requiredGroups">
      <xsl:sequence select="$requiredGroups"/>

      <xsl:for-each select="$requiredGroups">
        <xsl:call-template name="getRequiredGroups">
          <xsl:with-param name="groupNode" select="."/>
          <xsl:with-param name="groupProcessed" select="($groupProcessed,$requiredGroups)"/>
          <xsl:with-param name="compat-group" select="false()"/>
        </xsl:call-template>
      </xsl:for-each>
    </xsl:if>
    
  </xsl:template>
  
  
<!--
****
**** Recursive function to build a list of packages from a list of group.
****
**** Parameters:
****    groupList: list of groupNode to process (no check for duplicates)
****    processedPkgs : packages already found
****    compat-group: true if this group defines packages for compatibible architecture support (e.g. i386 for x86_64)
****    distrib-arch: distribution architecture
****    compat-arch: compatible architecture for distribution architecture, if any
****    compat-kernel-arch : kernel compatible architecture (used by glic)
****    kernel-arch : kernel architecture for the distribution
****    java-arch : Java archictecture (sometimes different from distribution arch)
--> 
  <xsl:template name="findGroupPkgs" as="element() *">
    <xsl:param name="compat-group"/>
    <xsl:param name="compat-arch"/>
    <xsl:param name="compat-kernel-arch"/>
    <xsl:param name="distrib-arch"/>
    <xsl:param name="kernel-arch"/>
    <xsl:param name="java-arch"/>
    <xsl:param name="groupList" select="()" as="element() *"/>
    <xsl:param name="processedPkgs" select="()" as="element() *"/>

    <xsl:if test="not(empty($groupList))">

      <!-- Pull first value out of the queue. --> 
      <xsl:variable name="token" as="element()">
        <xsl:sequence select="subsequence($groupList,1,1)"/>
      </xsl:variable>

    <xsl:variable name="token-compat">
      <xsl:choose>
        <xsl:when test="$token/biarchonly">
          <xsl:value-of select="$token/biarchonly"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="false()"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

      <xsl:if test="$debug-level > 1">
        <xsl:message>
          <xsl:text>findGroupPkgs - Queue : </xsl:text>
          <xsl:value-of select="count($groupList)"/>
          <xsl:text>, Processed </xsl:text>
          <xsl:value-of select="count($processedPkgs)"/>
          <xsl:text>, Current group </xsl:text>
          <xsl:value-of select="string($token/id)"/>
          <xsl:text>)</xsl:text>
        </xsl:message>
      </xsl:if>


      <!-- Get the list of package entries corresponding to the
           name of required packages. There should be no duplicates.
           Packages from required groups are only for architecture
           $distrib-arch or noarch, or compat-arch or noarch if this is
           a compatibility group -->          
      <xsl:variable name="requiredPkgList" as="element() *">
        <xsl:for-each select="$token/packagelist/packagereq">
          <xsl:call-template name="findPkgEntry" >
            <xsl:with-param name="pkgName" select="string(.)"/>
            <xsl:with-param name="compat-group" select="false()"/>
            <xsl:with-param name="compat-arch" select="$compat-arch"/>
            <xsl:with-param name="compat-kernel-arch" select="$compat-kernel-arch"/>
            <xsl:with-param name="distrib-arch" select="$distrib-arch"/>
            <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
            <xsl:with-param name="java-arch" select="$java-arch"/>
          </xsl:call-template>
        </xsl:for-each>
      </xsl:variable>

      <!-- Return the packages not already included -->
      <xsl:variable name="newPkgs" as="element() *">
        <xsl:for-each select="$requiredPkgList">
          <xsl:choose>
            <xsl:when test="not(count(.|$processedPkgs) = count($processedPkgs))">
              <xsl:sequence select="."/>
              <xsl:if test="$debug-level > 1">
                <xsl:message>
                  <xsl:text>findGroupPkgs - package added :  </xsl:text>
                  <xsl:value-of select="string(./id)"/>
                  <xsl:text> (arch=</xsl:text>
                  <xsl:value-of select="string(./arch)"/>
                  <xsl:text>)</xsl:text>
                </xsl:message>
              </xsl:if>
            </xsl:when>
          </xsl:choose>
        </xsl:for-each>
      </xsl:variable>
      
      <!-- Return the list of not yet included packages -->
      <xsl:sequence select="$newPkgs"/>
      
      <!-- Recrusively process every group in the group list -->
      <xsl:call-template name="findGroupPkgs">
        <xsl:with-param name="groupList" select="remove($groupList,1)"/>
        <xsl:with-param name="processedPkgs" select="($processedPkgs,$newPkgs)"/>
        <xsl:with-param name="compat-arch" select="$compat-arch"/>
        <xsl:with-param name="compat-kernel-arch" select="$compat-kernel-arch"/>
        <xsl:with-param name="distrib-arch" select="$distrib-arch"/>
        <xsl:with-param name="kernel-arch" select="$kernel-arch"/>
        <xsl:with-param name="java-arch" select="$java-arch"/>
        <xsl:with-param name="compat-group" select="$compat-group"/>
      </xsl:call-template>

    </xsl:if>

  </xsl:template>
  
 
<!--
****
**** Retrieve a package entry from dependency db from a package name.
**** This template must guess the appropriate package architecture,
**** according to groupe type (compatibility or native), as comps.xml
**** doesn't specify the architecture of required RPMs. The algorithm
**** used must be kept consistent with a similar algorithm used in
**** rpmRequires.pl.
****
**** Parameters:
****    pkgName: packageName to process
****    compat-group: true if this group defines packages for compatibible architecture support (e.g. i386 for x86_64)
****    distrib-arch: distribution architecture
****    compat-arch: compatible architecture for distribution architecture, if any
****    compat-kernel-arch : kernel compatible architecture (used by glic)
****    kernel-arch : kernel architecture for the distribution
****    java-arch : Java archictecture (sometimes different from distribution arch)
--> 
  <xsl:template name="findPkgEntry" as="element() *">
    <xsl:param name="pkgName" />
    <xsl:param name="compat-group"/>
    <xsl:param name="compat-arch"/>
    <xsl:param name="compat-kernel-arch"/>
    <xsl:param name="distrib-arch"/>
    <xsl:param name="kernel-arch"/>
    <xsl:param name="java-arch"/>

    <xsl:variable name="pkgArchs" select="$depdbcontent/*/pkg[string(id)=$pkgName]/arch"/>

    <xsl:variable name="rpmArch">
      <xsl:choose>
        <!-- Some packages are listed but always missing like elilo, acpid... -->
        <xsl:when test="count($pkgArchs) = 0">
          <xsl:message>
            <xsl:text>    WARNING: RPM </xsl:text><xsl:value-of select="$pkgName"/>
            <xsl:text> not found with any arch</xsl:text>
          </xsl:message>
        </xsl:when>
        
        <!-- noarch RPMs are acceptable as a dependency for any other RPM architectures.
             Use it if there is only one entry. The same RPM cannot exist both with a defined
             architecture and noarch. -->
        <xsl:when test="index-of($pkgArchs,'noarch') > 0">
          <xsl:choose>
            <xsl:when test="count($pkgArchs) = 1">
              <xsl:value-of select="'noarch'"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:message terminate="yes">
                <xsl:text>    ERROR: both noarch and other architecture found for package </xsl:text>
                <xsl:value-of select="$pkgName"/>
              </xsl:message>
             </xsl:otherwise>
          </xsl:choose>
        </xsl:when>
        
        <xsl:otherwise>
          <xsl:choose>
            <!-- Dependency for a RPM part of a compatibility group can be of any arch
                present in the distribution. Try compat-kernel-arch if defined, then compat-arch,
                distrib-arch and java-arch if defined. If just one RPM has the required name, use
                its architecture. -->
            <xsl:when test="$compat-group = true()">
              <xsl:choose>
                <xsl:when test="$compat-kernel-arch and
                                index-of($pkgArchs,$compat-kernel-arch) > 0">
                  <xsl:value-of select="$compat-kernel-arch"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:choose>
                    <xsl:when test="$compat-arch and
                                    index-of($pkgArchs,$compat-arch) > 0">
                      <xsl:value-of select="$compat-arch"/>
                    </xsl:when>
                    <xsl:otherwise>
                      <xsl:choose>
                        <xsl:when test="index-of($pkgArchs,$distrib-arch) > 0">
                          <xsl:value-of select="$distrib-arch"/>
                        </xsl:when>
                        <xsl:otherwise>
                          <xsl:choose>
                            <xsl:when test="$java-arch and
                                            index-of($pkgArchs,$java-arch) > 0">
                              <xsl:value-of select="$java-arch"/>
                            </xsl:when>
                            <xsl:otherwise>
                              <xsl:choose>
                                <xsl:when test="count($pkgArchs) = 1">
                                  <xsl:message>
                                    <xsl:text>    WARNING: expected architectures not found for compatibility package </xsl:text>
                                    <xsl:value-of select="$pkgName"/>
                                    <xsl:text>&#xa;             Using the only architecture available (</xsl:text>
                                    <xsl:value-of select="string($pkgArchs)"/><xsl:text>)</xsl:text>
                                  </xsl:message>
                                  <xsl:value-of select="string($pkgArchs)"/>
                                </xsl:when>
                                <xsl:otherwise>
                                  <xsl:message terminate="yes">
                                    <xsl:text>    ERROR: no compatible architecture found for package </xsl:text>
                                    <xsl:value-of select="$pkgName"/><xsl:text> (internal error)</xsl:text>
                                  </xsl:message>
                                </xsl:otherwise>
                              </xsl:choose>
                            </xsl:otherwise>
                          </xsl:choose>
                        </xsl:otherwise>
                      </xsl:choose>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:when>
            
            <!-- Not a compatibility group : allowed RPM archs are kernel-arch, distrib-arch, java-arch -->
            <xsl:otherwise>
              <xsl:choose>
                <xsl:when test="index-of($pkgArchs,$kernel-arch) > 0">
                  <xsl:value-of select="$kernel-arch"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:choose>
                    <xsl:when test="index-of($pkgArchs,$distrib-arch) > 0">
                      <xsl:value-of select="$distrib-arch"/>
                    </xsl:when>
                    <xsl:otherwise>
                      <xsl:choose>
                        <xsl:when test="$java-arch and
                                        index-of($pkgArchs,$java-arch) > 0">
                          <xsl:value-of select="$java-arch"/>
                        </xsl:when>
                        <xsl:otherwise>
                          <xsl:choose>
                            <xsl:when test="count($pkgArchs) = 1">
                              <xsl:message>
                                <xsl:text>    WARNING: expected architectures not found for package </xsl:text>
                                <xsl:value-of select="$pkgName"/>
                                <xsl:text>&#xa;             Using the only architecture available (</xsl:text>
                                <xsl:value-of select="string($pkgArchs)"/><xsl:text>)</xsl:text>
                              </xsl:message>
                              <xsl:value-of select="string($pkgArchs)"/>
                            </xsl:when>
                            <xsl:otherwise>
                              <xsl:message terminate="yes">
                                <xsl:text>    ERROR: no compatible architecture found for package </xsl:text>
                                <xsl:value-of select="$pkgName"/><xsl:text> (internal error)</xsl:text>
                             </xsl:message>
                            </xsl:otherwise>
                          </xsl:choose>
                        </xsl:otherwise>
                      </xsl:choose>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
   
    <xsl:variable name="pkgNode" as="element() *" 
                  select="$depdbcontent/*/pkg[(string(id) = $pkgName) and (string(arch) = $rpmArch)]"/>

    <xsl:if test="count($pkgNode) > 1">
      <xsl:message>
        <xsl:text>    WARNING: Dependency DB inconsistency : several matching packages found for  </xsl:text>
        <xsl:value-of select="$pkgName"/><xsl:text> (arch=</xsl:text>
        <xsl:value-of select="$rpmArch"/><xsl:text>)</xsl:text>
      </xsl:message>
    </xsl:if>
 
    <xsl:if test="$debug-level > 0">
      <xsl:choose>
        <!-- If may happend that a required RPM doesn't exist in the distribution... Ignore it. -->
        <xsl:when test="count($pkgNode) = 0">
          <xsl:message>
            <xsl:text>findPkgEntry - No packages found matching </xsl:text>
            <xsl:value-of select="$pkgName"/><xsl:text> (arch=</xsl:text>
            <xsl:value-of select="$rpmArch"/><xsl:text>)</xsl:text>
          </xsl:message>
        </xsl:when>
        <xsl:otherwise>
          <xsl:message>
            <xsl:text>findPkgEntry - Package found : </xsl:text>
            <xsl:value-of select="string($pkgNode[1]/id)"/><xsl:text> (arch=</xsl:text>
            <xsl:value-of select="string($pkgNode[1]/arch)"/>
            <xsl:text>, compatibility group=</xsl:text>
            <xsl:value-of select="$compat-group"/>
            <xsl:text>)</xsl:text>
          </xsl:message>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:if>

    <!-- Return the node found. Handle properly buggy dependency DB with several entries
         for the same package. -->
    <xsl:sequence select="$pkgNode[1]"/>
        
  </xsl:template>
  
  
<!--
****
**** Recursive function which takes a single node and recursively 
**** finds all of the dependencies.
****
**** Parameters:
****    groupNode: the group node to process
****
--> 
  <xsl:template name="findGroupDependencies" as="xsd:string*">

    <!-- Define the parameter; there is no default value. -->
    <xsl:param name="groupNode"/>

    <!-- Get the ID and add this to the output. -->
    <xsl:variable name="id" select="string(id)"/>
    <xsl:sequence select="$id"/>

    <!-- Process appropriate nodes. -->
    <xsl:for-each select="/*/group[grouplist/groupreq = $id]">
      <xsl:call-template name="findGroupDependencies">
        <xsl:with-param name="groupNode" select="."/>
      </xsl:call-template>
    </xsl:for-each>

  </xsl:template>


<!--
****
**** Recursive function which takes a single node and recursively 
**** finds all of the dependencies.
****
**** Parameters:
****    queue: packages to process (<pkg></pkg>)
****    processed: packages already processed
****
--> 
  <xsl:template name="collectPkgDependencies" as="element() *">

    <!-- Define the parameter; there is no default value. -->
    <xsl:param name="pkgList" select="()" as="element() *" />
    <xsl:param name="processedPkgs" select="()" as="element() *" />

    <!-- Process if the pkgList isn't empty. -->
    <xsl:if test="not(empty($pkgList))">

      <!-- Pull first value out of the pkgList. --> 
      <xsl:variable name="token" as="element()">
        <xsl:sequence select="subsequence($pkgList,1,1)"/>
      </xsl:variable>

      <xsl:if test="$debug-level > 1">
        <xsl:message>
          <xsl:text>collectPkgDependencies - Queue : </xsl:text>
          <xsl:value-of select="count($pkgList)"/>
          <xsl:text>, Processed </xsl:text>
          <xsl:value-of select="count($processedPkgs)"/>
          <xsl:text>, Current package </xsl:text>
          <xsl:value-of select="string($token/id)"/>
          <xsl:text> (arch=</xsl:text>
          <xsl:value-of select="string($token/arch)"/>
          <xsl:text>)</xsl:text>
        </xsl:message>
      </xsl:if>

      <!-- Add this to the output of this template! -->
      <xsl:sequence select="$token"/>

      <!-- Look in dependency db for a package matching rpm name and arch. -->
      <xsl:variable name="newPkgs" as="element() *">
        <xsl:for-each select="$token/dep">
          <xsl:variable name="pkgtmp" select="$depdbcontent/*/pkg[(id = current()/rpm) and (arch = current()/arch)]"/>
          <xsl:variable name="pkg" as="element() *">
            <xsl:choose>
              <!-- There is normally only one matching package but handle properly
                   a buggy dependency DB where there is several entries for the same RPM/arch -->
              <xsl:when test="count($pkgtmp) > 1">
                <xsl:sequence select="$pkgtmp[1]"/>
                <xsl:choose>
                  <xsl:when test="$ignore.duplicates = true()">
                    <xsl:message terminate='no'>
                      <xsl:text>WARNING: duplicated entries (</xsl:text>
                      <xsl:value-of select="count($pkgtmp)"/><xsl:text>) found in dependency DB for package </xsl:text>
                      <xsl:value-of select="string($pkgtmp[1]/id)"/><xsl:text> (</xsl:text>
                      <xsl:value-of select="string($pkgtmp[1]/arch)"/><xsl:text>)</xsl:text>
                    </xsl:message>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:message terminate='yes'>
                      <xsl:text>ERROR: duplicated entries (</xsl:text>
                      <xsl:value-of select="count($pkgtmp)"/><xsl:text>) found in dependency DB for package </xsl:text>
                      <xsl:value-of select="string($pkgtmp[1]/id)"/><xsl:text> (</xsl:text>
                      <xsl:value-of select="string($pkgtmp[1]/arch)"/>
                      <xsl:text>)&#xa;Use option ignore.duplicates to ignore this error.</xsl:text>
                    </xsl:message>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:when>
              <xsl:otherwise>
                <xsl:sequence select="$pkgtmp"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <xsl:choose>
            <xsl:when test="$pkg">
              <xsl:variable name="allpkgs" select="$pkgList | $processedPkgs"/>
              <xsl:if test="not(count($pkg|$allpkgs) = count($allpkgs))">
                <xsl:sequence select="$pkg"/>

                <xsl:if test="$debug-level > 1">
                  <xsl:message>
                    <xsl:text>collectPkgDependencies - package added :  </xsl:text>
                    <xsl:value-of select="string($pkg/id)"/>
                    <xsl:text> (arch=</xsl:text>
                    <xsl:value-of select="string($pkg/arch)"/>
                    <xsl:text>) </xsl:text>
                  </xsl:message>
                </xsl:if>
              </xsl:if>
            </xsl:when>
            <xsl:otherwise>
              <xsl:choose>
                <xsl:when test="$ignore.missing.rpm = true()">
                  <xsl:message terminate="no">
                    <xsl:text>    WARNING : Missing dependency RPM </xsl:text>
                    <xsl:value-of select="string(./rpm)"/>
                    <xsl:text> (arch=</xsl:text>
                    <xsl:value-of select="string(./arch)"/>
                    <xsl:text>) for RPM </xsl:text>
                    <xsl:value-of select="string($token/id)"/>
                    <xsl:text> (arch=</xsl:text>
                    <xsl:value-of select="string($token/arch)"/>
                    <xsl:text>)</xsl:text>
                  </xsl:message>                </xsl:when>
                <xsl:otherwise>
                  <xsl:message terminate="yes">
                    <xsl:text>    ERROR : Missing dependency RPM </xsl:text>
                    <xsl:value-of select="string(./rpm)"/>
                    <xsl:text> (arch=</xsl:text>
                    <xsl:value-of select="string(./arch)"/>
                    <xsl:text>) for RPM </xsl:text>
                    <xsl:value-of select="string($token/id)"/>
                    <xsl:text> (arch=</xsl:text>
                    <xsl:value-of select="string($token/arch)"/>
                    <xsl:text>)&#xa;Use option ignore.missing.rpm='true' to ignore this error.</xsl:text>
                  </xsl:message>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
      </xsl:variable>

      <!-- Remove processed node from pkgList; add to processed queue. -->
      <xsl:call-template name="collectPkgDependencies">
        <xsl:with-param name="pkgList" select="(remove($pkgList,1),$newPkgs)"/>
        <xsl:with-param name="processedPkgs" select="($processedPkgs,$token)"/>
      </xsl:call-template>

    </xsl:if>

  </xsl:template>


<!--
****
**** Make the default template including the default groups.
****
--> 
  <xsl:template name="makeDefaultGroup">
    <xsl:param name="groups"/>

    <xsl:variable name="gname">
      <xsl:value-of select="concat($pan-prefix,'default')"/>
    </xsl:variable>

    <xsl:message>
      <xsl:value-of select="concat('WRITING: ',$dir-url,$gname,'.tpl')"/>
    </xsl:message>

    <xsl:result-document href="{$dir-url}{$gname}.tpl">

      <xsl:call-template name="header">
        <xsl:with-param name="name" select="$gname"/>
        <xsl:with-param name="desc" select="'default groups'"/>
      </xsl:call-template>

      <xsl:for-each select="$groups">
        <xsl:call-template name="writeGroupEntry">
          <xsl:with-param name="groupId" select="id"/>
          <xsl:with-param name="groupEnabled" select="default"/>
        </xsl:call-template>
      </xsl:for-each>

      <!-- Ensure a new line is added. -->
      <xsl:text>&#xa;</xsl:text>

    </xsl:result-document>

  </xsl:template>


<!--
****
**** Format and write a group entry.
****
**** Parameters:
****    groupId: name of group to process
****    groupEnabled : if false, group is commented out (used to
****                   build default template)
--> 
  <xsl:template name="writeGroupEntry">
    <xsl:param name="groupId"/>
    <xsl:param name="groupEnabled"/>

    <xsl:variable name="gname">
      <xsl:value-of select="$pan-prefix"/>
      <xsl:call-template name="lowerCase">
        <xsl:with-param name="str" select="$groupId"/>
      </xsl:call-template>
    </xsl:variable>

    <xsl:variable name="template-ns">
      <xsl:choose>
        <xsl:when test="$namespace and not($namespace='') and not($namespace=' ')">
          <xsl:value-of select="concat($namespace,'/')"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="''"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:variable name="dvalue">
      <xsl:choose>
        <xsl:when test="string($groupEnabled) = 'true'">
          <xsl:text></xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:text># </xsl:text>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:variable name="quote">'</xsl:variable>
    <xsl:value-of select="concat($dvalue,'include { ',$quote,$template-ns,$gname,$quote,' };')"/>
    <xsl:text>&#xa;</xsl:text>

  </xsl:template>


<!--
****
**** Format and write package entries
****
**** Kernel related packages are added using pkg_add() rather than pkg_repl() 
**** with support for multiple versions enabled. This allows to install several
**** versions of the kernel and switch between them at boot time. In addition
**** if the distribution support for kernel variants for SMP support (smp, largesmp...),
**** like SL4, add only one package entry using KERNEL_VARIANT PAN variable.  
**** Kernel related packages have a name starting with 'kernel-'. 
****
**** Some other packages (glibc, openssl) are
**** added with an architecture different from the base architecture.
****
**** Parameters:
****    pkgList: packages to process
****    compat-group: if true, this group is a compatibility group
****
--> 
  <xsl:template name="writePkgEntries">
    <xsl:param name="pkgList" select="()" as="element() *"/>
    <xsl:param name="compat-group" select="false()"/>
    <xsl:param name="kernel-arch"/>

    <xsl:for-each select="$pkgList">
      <xsl:sort select="string(id)"/>
      
      <xsl:if test="$debug-level > 1">
        <xsl:message>
          <xsl:text>pkgEntry - Writing </xsl:text>
          <xsl:value-of select="string(id)"/>
        </xsl:message>
      </xsl:if>

      <xsl:choose>
        <!-- Problematic RPM in SL (unsupported drivers, fs, ...) : disable it.
             This RPM leads to several problem : missing symbols, smp/non smp selection... -->
        <xsl:when test="matches(string(id), '^kernel.*-unsupported$')">
          <xsl:text>#"/software/packages"=pkg_add("</xsl:text>
          <xsl:value-of select="id"/><xsl:text>","</xsl:text>
          <xsl:value-of select="version"/>
          <xsl:text>",PKG_ARCH_KERNEL,"multi");&#xa;</xsl:text>
        </xsl:when>

        <!-- Kernel related RPMs : add one entry for each RPM with kernel variant appended.
             Kernel variants are appended at the end of RPM name. -->
        <xsl:when test="(string(id) = 'kernel') or matches(string(id),'^kernel-module.*$')">
          <xsl:variable name="rpmArch" select="arch"/>
          <xsl:choose>
            <xsl:when test="$rpmArch = $kernel-arch" >
              <xsl:variable name="rpmname">
                <xsl:choose>
                  <!-- Kernel RPM (variant has been removed by rpmProvides/Requires) -->
                  <xsl:when test="string(id) = 'kernel'">
                    <xsl:value-of select="'PKG_KERNEL_RPM_NAME'"/>
                  </xsl:when>
                  <!-- Kernel modules : last part of RPM name is kernel version -->
                  <xsl:otherwise>
                    <xsl:choose>
                      <xsl:when test="$kernel.version.explicit = false()">
                        <xsl:text>"</xsl:text>
                        <xsl:value-of select="replace(string(id),'-\d.*$','')" /><xsl:text>-"+KERNEL_VERSION_NUM</xsl:text>
                      </xsl:when>
                      <xsl:otherwise>
                        <xsl:text>"</xsl:text><xsl:value-of select="string(id)"/><xsl:text>"</xsl:text>
                      </xsl:otherwise>
                    </xsl:choose>
                    <xsl:text>+KERNEL_VARIANT</xsl:text>
                  </xsl:otherwise>
                 </xsl:choose>
              </xsl:variable>
              <!-- RPM version : use actual version name, except for kernel RPM when
                   kernel.version.explicit is false -->
              <xsl:variable name="rpmversion">
                <xsl:choose>
                  <xsl:when test="(string(id) = 'kernel') and ($kernel.version.explicit = false())">
                    <xsl:text>KERNEL_VERSION_NUM</xsl:text>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:text>"</xsl:text><xsl:value-of select="version"/><xsl:text>"</xsl:text>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:variable>
              <xsl:if test="string(id) = 'kernel'">
                <xsl:text># PKG_KERNEL_NAME can be overridden if not conforming to standard naming scheme
variable PKG_KERNEL_NAME ?= '</xsl:text><xsl:value-of select="string(id)"/><xsl:text>'; 
# PKG_KERNEL_RPM_NAME can be overridden if not conforming to standard naming scheme
variable PKG_KERNEL_RPM_NAME ?= {
  rpmname = PKG_KERNEL_NAME;
  if ( length(KERNEL_VARIANT) > 0 ) {
    rpmname = rpmname + '-' + KERNEL_VARIANT;
  };
  rpmname;
};&#xa;</xsl:text>
              </xsl:if>
              <xsl:text>"/software/packages"=pkg_add(</xsl:text>
              <xsl:value-of select="$rpmname"/><xsl:text>,</xsl:text>
              <xsl:value-of select="$rpmversion"/>
              <xsl:text>,PKG_ARCH_KERNEL,"multi");&#xa;</xsl:text>
            </xsl:when>
            <xsl:otherwise>
              <!-- A noarch kernel related RPM example is kernel-doc.
                   Disable (comment out) other packages. -->
              <xsl:if  test="$rpmArch != 'noarch'">
                <xsl:text>#</xsl:text>
              </xsl:if>
              <xsl:text>"/software/packages"=pkg_add("</xsl:text>
              <xsl:value-of select="id"/><xsl:text>","</xsl:text>
              <xsl:value-of select="version"/><xsl:text>","</xsl:text>
              <xsl:value-of select="arch"/><xsl:text>","multi");&#xa;</xsl:text>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:when>
        <xsl:when test="(string(id) = 'glibc') and (string(arch) = $kernel-arch)">
          <xsl:text>"/software/packages"=pkg_repl("</xsl:text>
          <xsl:value-of select="id"/><xsl:text>","</xsl:text>
          <xsl:value-of select="version"/>
          <xsl:text>",PKG_ARCH_GLIBC);&#xa;</xsl:text>
        </xsl:when>
        <xsl:when test="(string(id) = 'openssl') and (string(arch) = $kernel-arch)">
          <xsl:text>"/software/packages"=pkg_repl("</xsl:text>
          <xsl:value-of select="id"/><xsl:text>","</xsl:text>
          <xsl:value-of select="version"/>
          <xsl:text>",PKG_ARCH_OPENSSL);&#xa;</xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:text>"/software/packages"=pkg_repl("</xsl:text>
          <xsl:value-of select="id"/><xsl:text>","</xsl:text>
          <xsl:value-of select="version"/><xsl:text>","</xsl:text>
          <xsl:value-of select="arch"/><xsl:text>");&#xa;</xsl:text>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>

  </xsl:template>




<!--
****
**** Write out a section header. 
****
--> 
  <xsl:template name="header">
    <xsl:param name="name"/>
    <xsl:param name="desc"/>

    <xsl:variable name="template-ns">
      <xsl:choose>
        <xsl:when test="$namespace and not($namespace='') and not($namespace=' ')">
          <xsl:value-of select="concat($namespace,'/')"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="''"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:text># Template generated by comps2pan.xsl - DO NOT EDIT
#
# </xsl:text><xsl:value-of select="$desc"/>
<xsl:text>
#

unique template </xsl:text><xsl:value-of select="concat($template-ns,$name)"/><xsl:text>;

</xsl:text>

  </xsl:template>


<!--
****
****  Convert a string to an uppercase equivalent
****
--> 
  <xsl:template name="upperCase">
    <xsl:param name="str"/>
    <xsl:value-of select="translate(string($str),
                          '_-abcdefghijklmnopqrstuvwxyz',
                          '__ABCDEFGHIJKLMNOPQRSTUVWXYZ')" />
  </xsl:template>

<!--
****
****  Convert a string to an lowercase equivalent
****
--> 
  <xsl:template name="lowerCase">
    <xsl:param name="str"/>
    <xsl:value-of select="translate(string($str),
                          '_-ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                          '__abcdefghijklmnopqrstuvwxyz')" />
  </xsl:template>



</xsl:stylesheet>

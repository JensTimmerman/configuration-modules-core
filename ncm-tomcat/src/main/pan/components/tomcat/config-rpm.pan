# ${license-info}
# ${developer-info}
# ${author-info}



unique template components/tomcat/config-rpm;

include components/tomcat/schema;

 
# Package to install
"/software/packages"=pkg_repl('ncm-tomcat', '1.0.4-1', 'noarch');
"/software/packages"=pkg_repl("perl-XML-Parser");

"/software/components/tomcat/dependencies/pre" ?= list("spma");
"/software/components/tomcat/active" ?= false;
"/software/components/tomcat/dispatch" ?= false;

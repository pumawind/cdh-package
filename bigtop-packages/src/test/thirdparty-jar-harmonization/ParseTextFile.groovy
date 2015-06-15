#!/usr/bin/env groovy
// Copyright (c) 2015 Cloudera, Inc. All rights reserved.

import java.util.jar.JarFile;
import groovy.sql.Sql
import groovy.json.JsonSlurper;

// Parse the xml file, and does two things:
// 1. Generates two files - one that contains stats for each jar and the other that ties each of these
//                          jars to specific components.
// 2. Bulk loads this into a database for analysis.
public class ParseTextFile {

  public static void main(String[] args) {
    // This file is expected to be present, and is generated by the script
    // thirdparty_jar_harmonization.sh.
    def out = new XmlParser().parse("./xml_formatted_output.xml");
    File f = new File("./jar_stats.txt");
    File f1 = new File("./jar_component_map.txt");

    // Ensure that these files are not present before we start
    if ( f.exists() ) {
        f.delete();
    }
    if ( f1.exists()) {
        f.delete();
    }

    PrintWriter statsWriter = new PrintWriter(f)
    PrintWriter jarComponentWriter = new PrintWriter(f1)
    def date= out.date.text()
    def parcelName = out.parcel.text()
    def cdhVersion = out.cdh_version.text()
    def separator="+++"

    try {
        // Parse the XML and do formatting so that the resulting output file.
        // can be fed as bulk.
        out.jarFile.each {

          // Reinitialize the list on each iteration.
          ArrayList<String> statsTableList = new ArrayList<String>();
          ArrayList<String> componentMapList = new ArrayList<String>();

          def jarName= it.'jarFileName'.text()
          def jarCount= it.'jarFileCount'.text()
          def jarNameSearchPattern=it.'jarFileSearchPattern'.text()
          def jarVersions= it.'jarFileWithVersions'.text().trim().replaceAll("\n", ",")
          def jarComponentMap= it.'jarFileSymlinks'.text().trim().replaceAll("\n", ",")
          def componentNameJarMap = [:]
          jarComponentMap.split(",").each  {
            // If the string is null or empty, return.
            if ( ! it?.trim()) {
              return;
            }
            def local_splitString=it.split("->");
            def local_compoenentName=local_splitString[0]
            def local_jarName=local_splitString[1]
            if(componentNameJarMap.containsKey(local_compoenentName)) {
                def local_list_jars = componentNameJarMap[local_compoenentName]
                componentNameJarMap.remove(local_compoenentName)
                componentNameJarMap[local_compoenentName]=local_list_jars+","+local_jarName
            } else {
                  componentNameJarMap[local_compoenentName]=local_jarName
            }
          }

          // Data to be inserted into the stats table.
          statsTableList.add(date);
          statsTableList.add(jarName);
          statsTableList.add(jarCount);
          statsTableList.add(jarNameSearchPattern);
          statsTableList.add(jarVersions);
          statsTableList.add(parcelName);
          statsTableList.add(cdhVersion);
          def statsRow = Utility.constructStringFromList(statsTableList, separator);
          statsWriter.println(statsRow);

          // Data to be inserted into the component map table.
          componentNameJarMap.each { entry ->

            // Clear the Array list before each line is written.
            componentMapList.clear();

            componentMapList.add(date);
            componentMapList.add(jarName);
            componentMapList.add(entry.key);
            componentMapList.add(entry.value);
            componentMapList.add(parcelName);
            componentMapList.add(cdhVersion);
            def componentMapRow = Utility.constructStringFromList(componentMapList, separator);
            jarComponentWriter.println(componentMapRow);
          }
        }
    } finally {
        statsWriter.close()
        jarComponentWriter.close()
    }

    def dbConnection = Utility.getDbConnection();

    try {
        def isExists = dbConnection.firstRow("SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='thirdparty_harmonization'")
        // Create schema if it does not already exist.
        if (! isExists) {
          def sqlFileContents = new File("./create_schema.sql").text
          dbConnection.execute (sqlFileContents)
        }

        dbConnection.execute ("USE thirdparty_harmonization")

        // Verify that this parcel has not already been analyzed
        // ToDo: Move this check even before we download the parcel. For now, let it sit here.
        def isDataExists=dbConnection.firstRow("SELECT parcel_name from thirdparty_jars_stats where parcel_name=? ;",parcelName)
        if (! isDataExists) {
          isDataExists=dbConnection.firstRow("SELECT parcel_name from thirdparty_jars_stats_history where parcel_name=? ;",parcelName)
        }

        if (! isDataExists ) {

          println "Data does not exist. Loading"

          Utility.insertIntoHistoryTables();

          //  Load stats from the current run.
          def workingDir = new File(".").getCanonicalPath()
          dbConnection.execute("LOAD DATA LOCAL INFILE '${Sql.expand(workingDir)}/jar_stats.txt' INTO TABLE thirdparty_jars_stats FIELDS TERMINATED BY '${Sql.expand(separator)}';")
          dbConnection.execute ("LOAD DATA LOCAL INFILE '${Sql.expand(workingDir)}/jar_component_map.txt' INTO TABLE thirdparty_jars_component_map FIELDS TERMINATED BY '${Sql.expand(separator)}';")
        } else {
          println("Tables not populated for parcel $parcelName as data already exits.")
        }
      }finally {
          try {
            dbConnection.close();
            } catch (Exception e) {
                // Nothing to do.
            }
       }
        println "Finished loading database"
  }
}

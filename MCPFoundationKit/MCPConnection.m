//
//  MCPConnection.m
//  SMySQL
//
//  Created by serge cohen (serge.cohen@m4x.org) on Sat Dec 08 2001.
//  Copyright (c) 2001 Serge Cohen. All rights reserved.
//
//  This code is free software; you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or any later version.
//
//  This code is distributed in the hope that it will be useful, but WITHOUT ANY
//  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
//  details.
//
//  For a copy of the GNU General Public License, visit <http://www.gnu.org/> or
//  write to the Free Software Foundation, Inc., 59 Temple Place--Suite 330,
//  Boston, MA 02111-1307, USA.
//
//  More info at <http://mysql-cocoa.sourceforge.net/>
//
// $Id: MCPConnection.m,v 1.6 2004/08/09 16:04:25 sergecohen Exp $
// $Author: sergecohen $


#import "MCPConnection.h"
#import "MCPResult.h"
#import "MCPNumber.h"
#import "MCPNull.h"

#define MYSQL_CHARSET "latin1"

const unsigned int	kMCPConnectionDefaultOption = CLIENT_COMPRESS;
const char           *kMCPConnectionDefaultSocket = MYSQL_UNIX_ADDR;
const unsigned int	kMCPConnection_Not_Inited = 1000;

// For debugging:
//static FILE		*MCPConnectionLogFile;



@implementation MCPConnection
/*"
!{ $Id: MCPConnection.m,v 1.6 2004/08/09 16:04:25 sergecohen Exp $ }
!{ $Author: sergecohen $ }
 
This class is used to keep a connection with a MySQL server, it correspond to the MYSQL structure of the C API, or the database handle of the PERL DBI/DBD interface.

You have to start any work on a MySQL server by getting a working MCPConnection object.

Most likely you will use this kind of code:

!{
    MCPConnection	*theConnec = [MCPConnection alloc];
    MCPResult	*theRes;
    
    theConnec = [theConnec initToHost:@"albert.com" withLogin:@"toto" password:@"albert" usingPort:0];
    [theConnec selectDB:@"db1"];
    theRes = [theConnec queryString:@"select * from table1"];
    ...
}

#{NOTE} Failing to properly release your MCPConnection(s) object might cause a MySQL crash!!! (recovered if the
server was started using mysqld_safe).

"*/

+ (NSDictionary *) getMySQLLocales
/*"
Gets a proper Locale dictionary to use formater to parse strings from MySQL.
For example strings representing dates should give a proper Locales for use with methods such as NSDate::dateWithNaturalLanguageString: locales:
"*/
{
    NSMutableDictionary	*theLocalDict = [NSMutableDictionary dictionaryWithCapacity:12];
    
    [theLocalDict setObject:@"." forKey:@"NSDecimalSeparator"];
    
    return [NSDictionary dictionaryWithDictionary:theLocalDict];
}


+ (NSStringEncoding) encodingForMySQLEncoding:(const char *) mysqlEncoding
/*"
Gets a proper NSStringEncoding according to the given MySQL charset.

MySQL 4.0 offers this charsets:
big5 cp1251 cp1257 croat czech danish dec8 dos estonia euc_kr gb2312 gbk german1 greek hebrew hp8 hungarian koi8_ru koi8_ukr latin1 latin1_de latin2 latin5 sjis swe7 tis620 ujis usa7 win1250 win1251ukr

 WARNING : incomplete implementation. Please, send your fixes.
"*/
{
    if (!strcmp(mysqlEncoding, "latin1")) {
        return NSISOLatin1StringEncoding;
    }
    if (!strcmp(mysqlEncoding, "latin2")) {
        return NSISOLatin2StringEncoding;
    }
    if (!strcmp(mysqlEncoding, "win1250")) {
        return NSWindowsCP1250StringEncoding;
    }
    if (!strcmp(mysqlEncoding, "cp1251")) {
        return NSWindowsCP1251StringEncoding;
    }
    if (!strcmp(mysqlEncoding, "euc_kr")) {
        return NSJapaneseEUCStringEncoding;
    }
    if (!strcmp(mysqlEncoding, "sjis")) {
        return  NSShiftJISStringEncoding;
    }
    
// default to iso latin 1, even if it is not exact (throw an exception?)    
    return NSISOLatin1StringEncoding;
}


+ (NSStringEncoding) defaultMySQLEncoding
/*"
Returns the default charset of the library mysqlclient used.
"*/
{
	
    return [MCPConnection encodingForMySQLEncoding:MYSQL_CHARSET];
}


+ (void) initialize
/*"
Initialize the class version to 2.3.1
"*/
{
    if (self = [MCPConnection class]) {
        [self setVersion:020301]; // Ma.Mi.Re -> MaMiRe
    }

// For debugging:
/*
    MCPConnectionLogFile = fopen("MCPConnection_debug.txt","a");
    NSLog(@"MCPConnectionLogFile = %p\n", MCPConnectionLogFile);
*/
    return;
}


- (id) init
/*"
Initialise a MySQLConnection without making a connection, most likely useless, except with !{setConnectionOption:withArgument:}.

Because this method is not making a connection to any MySQL server, it can not know already what the DB server encoding will be,
hence the encoding is set to some default (at present this is NSISOLatin1StringEncoding). Obviously this is reset to a proper
value as soon as a DB connection is performed.

#{I AM CURRENTLY NOT TESTING THIS METHOD, so it is likely to be buggy}... I'd be SUPER happy to ear/read your feed-back on this.
"*/
{
    if(self = [super init]) {
		mConnection = mysql_init(NULL);
		mConnected = NO;
		if (mConnection ==  NULL) {
			[self autorelease];
			return nil;
		}
		mEncoding = NSISOLatin1StringEncoding;
		mConnectionFlags = kMCPConnectionDefaultOption;
		//    mEncoding = [MCPConnection encodingForMySQLEncoding:mysql_character_set_name(mConnection)];
		return self;
	} else 
		return nil;
}


- (id) initToHost:(NSString *) host withLogin:(NSString *) login password:(NSString *) pass usingPort:(int) port
/*"
Initialise a connection using a #{TCP/IP connection} with the given parameters (except if host is set to !{localhost}, in which case uses the default)

- host is the hostname or IP adress
- login is the user name
- pass is the password corresponding to the user name
- port is the TCP port to use to connect. If port = 0, uses the default port from mysql.h
"*/
{
	if(	self = [super init] ) {
		mEncoding = NSISOLatin1StringEncoding;
		if (mConnected) {
	// If a the connection is on, disconnect and reset it to default
			mysql_close(mConnection);
			mConnection = NULL;
		}
		else {
		}

		mConnection = mysql_init(mConnection);
		mConnected = NO;

		if (mConnection == NULL) {
			[self autorelease];
			return nil;
		}

		mConnectionFlags = kMCPConnectionDefaultOption;

		[self connectWithLogin:login password:pass host:host port:port socket:nil];
		return self;    
	} else
		return nil;
}


- (id) initToSocket:(NSString *) socket withLogin:(NSString *) login password:(NSString *) pass
/*"
Initialise a connection using a #{unix socket} with the given parameters

- socket is the path to the socket
- login is the user name
- pass is the password corresponding to the user name
"*/
{
    if(self = [super init]) {
		mEncoding = NSISOLatin1StringEncoding;
		if (mConnected) {
			// If a the connection is on, disconnect and reset it to default
			mysql_close(mConnection);
			mConnection = NULL;
		}
		else {
		}

		mConnection = mysql_init(mConnection);
		mConnected = NO;

		if (mConnection == NULL) {
			[self autorelease];
			return nil;
		}

		mConnectionFlags = kMCPConnectionDefaultOption;

		[self connectWithLogin:login password:pass host:NULL port:0 socket:socket];
		return self;
	} else
		return nil;
}
    

- (BOOL) setConnectionOption:(int) option toValue:(BOOL) value
/*"
#{IMPLEMENTED BUT NOT TESTED!!}

This method is to be used for getting special option for a connection, in which case the MCPConnection has to be inited with the init method, then option are selected, finally connection is done using one of the connect methods:

!{
    MCPConnection	*theConnect = [[MCPConnection alloc] init];
    [theConnect setConnectionOption: option toValue: value];
    [theConnect connectToHost:albert.com withLogin:@"toto" password:@"albert" port:0];
    ....
}

"*/
{
// So far do nothing except for testing if it's proper time for setting option 
// What about if some option where setted and a connection is made again with connectTo...
    if ((mConnected)  || (! mConnection)) {
        return FALSE;
    }
#warning Have to check the syntax of the following assignements:
    if (value) { //Set this option to true
        mConnectionFlags |= option;
    }
    else { //Set this option to false
        mConnectionFlags &= (! option);
    }
    return YES;
}


- (BOOL) connectWithLogin:(NSString *) login password:(NSString *) pass host:(NSString *) host port:(int) port socket:(NSString *) socket
/*"
The method used by !{initToHost:withLogin:password:usingPort:} and !{initToSocket:withLogin:password:}. Same information and use of the parameters:

     - login is the user name
     - pass is the password corresponding to the user name
     - host is the hostname or IP adress
     - port is the TCP port to use to connect. If port = 0, uses the default port from mysql.h
     - socket is the path to the socket (for the localhost)

The socket is used if the host is set to !{@"localhost"}, to an empty or a !{nil} string
For the moment the implementation might not be safe if you have a nil pointer to one of the NSString* variables (underestand: I don't know what the result will be).
"*/
{
	if( [login length] > 0 &&  [pass length] > 0) {
		const char	*theLogin = [self cStringFromString:login];
		const char	*theHost = [self cStringFromString:host];
		const char	*thePass = [self cStringFromString:pass];
		const char	*theSocket = [self cStringFromString:socket];
		void	*theRet;
		
		if (mConnected) {
			// Disconnect if it was already connected
			mysql_close(mConnection);
			mConnection = NULL;
			mConnected = NO;
			[self init];
		}
		
		if ([host isEqualToString:@""]) {
			theHost = NULL;
		}
		if (theSocket == NULL) {
			theSocket = kMCPConnectionDefaultSocket;
		}
		
		theRet = mysql_real_connect(mConnection, theHost, theLogin, thePass, NULL, port, theSocket, mConnectionFlags);
		if (theRet != mConnection) {
			return mConnected = NO;
		}
		mEncoding = [MCPConnection encodingForMySQLEncoding:mysql_character_set_name(mConnection)];
		/*
		 NSLog (@"Default encoding is %@\n", [NSString localizedNameOfStringEncoding:[NSString defaultCStringEncoding]]);
		 NSLog (@"MySQL encoding is %@\n", [NSString localizedNameOfStringEncoding:mEncoding]);
		 fprintf(MCPConnectionLogFile,"MySQLEncoding : %s\n", (const char *)[[NSString localizedNameOfStringEncoding:mEncoding] cString]);
		 */
		return mConnected = YES;
	} else 
		return mConnected = NO;
}


- (BOOL) selectDB:(NSString *) dbName
/*"
Selects a database to work with.
The MCPConnection object needs to be properly inited and connected to a server.
If a connection is not yet set or the selection of the database didn't work, returns NO. Returns YES in normal cases where the database is properly selected.

So far, if dbName is a nil pointer it will return NO (as if it cannot connect), most likely this will throw an exception in the future.
"*/
{
    if (dbName == nil) {
// Here we should throw an exception, impossible to select a databse if the string is indeed a nil pointer
        return NO;
    }
    if (mConnected) {
        const char	 *theDBName = [self cStringFromString:dbName];
        if (mysql_select_db(mConnection, theDBName) == 0) {
            return YES;
        }
    }
    return NO;
}


- (NSString *) getLastErrorMessage
/*"
Returns a string with the last MySQL error message on the connection.
"*/
{
    if (mConnection) {
        return [self stringWithCString:mysql_error(mConnection)];
    }
    else {
        return [NSString stringWithString:@"No connection initailized yet (MYSQL* still NULL)\n"];
    }
}

- (unsigned int) getLastErrorID
/*"
Returns the ErrorID of the last MySQL error on the connection.
"*/
{
    if (mConnection) {
        return mysql_errno(mConnection);
    }
    return kMCPConnection_Not_Inited;
}

- (BOOL) isConnected
/*"
Returns YES if the MCPConnection is connected to a DB, NO otherwise.
"*/
{
    return mConnected;
}

- (BOOL)checkConnection
/*"
Checks if the connection to the server is still on.
If not, tries to reconnect (changing no parameters from the MYSQL pointer).
This method just uses mysql_ping().
"*/
{
    return (BOOL)(! mysql_ping(mConnection));
}


- (NSString *) prepareBinaryData:(NSData *) theData
/*"
Takes a NSData object and transform it in a proper string for sending to the server in between quotes.
"*/
{
    const char		*theCDataBuffer = [theData bytes];
    unsigned int	theLength = [theData length];
    char		*theCEscBuffer = (char *)calloc(sizeof(char),(theLength*2) + 1);
    NSString		*theReturn;

    mysql_real_escape_string(mConnection, theCEscBuffer, theCDataBuffer, theLength);
    theReturn = [self stringWithCString:theCEscBuffer];
    free (theCEscBuffer);
    return theReturn;
}


- (NSString *) prepareString:(NSString *) theString
/*"
Takes a string and escape any special character (like single quote : ') so that the string can be used directly in a query.
"*/
{
    const char		*theCStringBuffer = [self cStringFromString:theString];
    unsigned int	theLength;
    char          *theCEscBuffer;
    NSString		*theReturn;

    if (theString == nil) {
#pragma warning This is not the best solution, here we loose difference between NULL and empty string.
// In the mean time, no one should call this method on a nil string, the test should be done before by the user of this method.
        return @"";
    }
    theLength = strlen(theCStringBuffer);
    theCEscBuffer = (char *)calloc(sizeof(char),(theLength * 2) + 1);
    mysql_real_escape_string(mConnection, theCEscBuffer, theCStringBuffer, theLength);
    theReturn = [self stringWithCString:theCEscBuffer];
    free (theCEscBuffer);
    return theReturn;    
}


- (NSString *) quoteObject:(id) theObject
/*" Use the class of the theObject to know how it should be prepared for usage with the database.
If theObject is a string, this method will put single quotes to both its side and escape any necessary
character using prepareString: method. If theObject is NSData, the prepareBinaryData: method will be
used instead.
For NSNumber object, the number is just quoted, for calendar dates, the calendar date is formatted in
the preferred format for the database.
   "*/
{
   if ((! theObject) || ([theObject isNSNull])) {
      return @"NULL";
   }
   if ([theObject isKindOfClass:[NSData class]]) {
      return [NSString stringWithFormat:@"'%@'", [self prepareBinaryData:(NSData *) theObject]];
   }
   if ([theObject isKindOfClass:[NSString class]]) {
      return [NSString stringWithFormat:@"'%@'", [self prepareString:(NSString *) theObject]];
   }
   if ([theObject isKindOfClass:[NSNumber class]]) {
      return [NSString stringWithFormat:@"%@", theObject];
   }
   if ([theObject isKindOfClass:[NSCalendarDate class]]) {
      return [NSString stringWithFormat:@"'%@'", [(NSCalendarDate *)theObject descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"]];
   }
   if ((nil == theObject) || ([theObject isKindOfClass:[NSNull class]])) {
      return @"NULL";
   }
// Default : quote as string:
   return [NSString stringWithFormat:@"'%@'", [self prepareString:[theObject description]]];
}


- (MCPResult *) queryString:(NSString *) query
/*"
Takes a query string and return an MCPResult object holding the result of the query.
 The returned MCPResult is not retained, the client is responsible for that (it's autoreleased before being returned). If no field are present in the result (like in an insert query), will return nil (#{difference from previous version implementation}). Though, if their is at least one field the result will be non nil (even if no row are selected).

 Note that if you want to use this method with binary data (in the query), you should use !{prepareBinaryData:} to include the binary data in the query string. Also if you want to include in your query a string containing any special character (\, ', " ...) then you should use !{prepareString}.
"*/
{
    MCPResult     *theResult = [MCPResult alloc];
    const char    *theCQuery = [self cStringFromString:query];
    int           theQueryCode;
// Temp for debugging:
/*
    NSMutableData	*theDefCQuery = [NSMutableData dataWithData:[query dataUsingEncoding:[NSString defaultCStringEncoding] allowLossyConversion:YES]];
    NSMutableData	*theIso1CQuery = [NSMutableData dataWithData:[query dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
    const char		*theDCQuery, *theICQuery;

    [theDefCQuery increaseLengthBy:1];
    [theIso1CQuery increaseLengthBy:1];
    theDCQuery = [theDefCQuery bytes];
    theICQuery = [theIso1CQuery bytes];
*/
//    NSLog (@"In queryString, query is : %s -in ObjC : %@-\n", theCQuery, query);
/*
    fprintf(MCPConnectionLogFile,"C string (MySQL enco.)   : ");
    fwrite((const void *)theCQuery, strlen(theCQuery), 1, MCPConnectionLogFile);
    fprintf(MCPConnectionLogFile,"\nC string (default enco.) : ");
    fwrite((const void *)theDCQuery, strlen(theDCQuery), 1, MCPConnectionLogFile);
    fprintf(MCPConnectionLogFile,"\nC string (iso1 enco.)    : ");
    fwrite((const void *)theICQuery, strlen(theICQuery), 1, MCPConnectionLogFile);
    fprintf(MCPConnectionLogFile,"\n");
*/
    if ((theQueryCode = mysql_query(mConnection, theCQuery)) == 0) {
        if (mysql_field_count(mConnection) != 0) {
            theResult = [theResult initWithMySQLPtr:mConnection encoding:mEncoding];
        }
        else {
//            NSLog (@"Query worked but gives no output\n");
//            [theResult init];
            return nil;
        }
    }
    else {
       NSLog (@"Problem in queryString error code is : %d, query is : %s -in ObjC : %@-\n", theQueryCode, theCQuery, query);
       NSLog(@"Error message is : %@\n", [self getLastErrorMessage]);
//        theResult = [theResult init]; // Old version...
       theResult = nil;
    }
    if (theResult) {
        [theResult autorelease];
    }
    return theResult;
}

- (my_ulonglong) affectedRows
/*"
Returns the number of affected rows by the last query.
"*/
{
    if (mConnected) {
        return mysql_affected_rows(mConnection);
    }
    return 0;
}


- (my_ulonglong) insertId
/*"
If the last query was an insert in a table having a autoindex column, returns the id (autoindexed field) of the last row inserted.
"*/
{
    if (mConnected) {
        return mysql_insert_id(mConnection);
    }
    return 0;
}


- (MCPResult *) listDBs
/*"
Just a fast wrapper for the more complex !{listDBsWithPattern:} method.
"*/
{
    return [self listDBsLike:nil];
}


- (MCPResult *) listDBsLike:(NSString *) dbsName
/*"
Returns a list of database which name correspond to the SQL regular expression in 'pattern'.
The comparison is done with wild card extension : % and _.
The result should correspond to the queryString:@"SHOW databases [LIKE wild]"; but implemented with mysql_list_dbs.
If an empty string or nil is passed as pattern, all databases will be shown.
"*/
{
    MCPResult	*theResult = [MCPResult alloc];
    MYSQL_RES		*theResPtr;

    if ((dbsName == nil) || ([dbsName isEqualToString:@""])) {
        if (theResPtr = mysql_list_dbs(mConnection, NULL)) {
            [theResult initWithResPtr: theResPtr encoding: mEncoding];
        }
        else {
            [theResult init];
        }
    }
    else {
        const char	*theCDBsName = (const char *)[[dbsName dataUsingEncoding: mEncoding allowLossyConversion: YES] bytes];
        if (theResPtr = mysql_list_dbs(mConnection, theCDBsName)) {
            [theResult initWithResPtr: theResPtr encoding: mEncoding];
        }
        else {
            [theResult init];
        }        
    }
    if (theResult) {
        [theResult autorelease];
    }
    return theResult;    
}


- (MCPResult *) listTables
/*"
Make sure a DB is selected (with !{selectDB:} method) first.
"*/
{
    return [self listTablesLike:nil];
}


- (MCPResult *) listTablesLike:(NSString *) tablesName
/*"
From within a database, give back the list of table which name correspond to tablesName (with wild card %, _ extension). Correspond to queryString:@"SHOW tables [LIKE wild]"; uses mysql_list_tables function.
If an empty string or nil is passed as tablesName, all tables will be shown.
WARNING: #{produce an error if no databases are selected} (with !{selectDB:} for example).
"*/
{
    MCPResult	*theResult = [MCPResult alloc];
    MYSQL_RES		*theResPtr;

    if ((tablesName == nil) || ([tablesName isEqualToString:@""])) {
        if (theResPtr = mysql_list_tables(mConnection, NULL)) {
            [theResult initWithResPtr: theResPtr encoding: mEncoding];
        }
        else {
            [theResult init];
        }
    }
    else {
        const char	*theCTablesName = (const char *)[[tablesName dataUsingEncoding: mEncoding allowLossyConversion: YES] bytes];
        if (theResPtr = mysql_list_tables(mConnection, theCTablesName)) {
            [theResult initWithResPtr: theResPtr encoding: mEncoding];
        }
        else {
            [theResult init];
        }
    }
    if (theResult) {
        [theResult autorelease];
    }
    return theResult;
}


- (MCPResult *) listTablesFromDB:(NSString *) dbName like:(NSString *) tablesName
/*"
List tables in DB specified by dbName and corresponding to pattern.
This method indeed issues a !{SHOW TABLES FROM dbName LIKE ...} query to the server.
This is done this way to make sure the selected DB is not changed by this method.
"*/
{
    MCPResult	*theResult;

    if ((tablesName == nil) || ([tablesName isEqualToString:@""])) {
        NSString	*theQuery = [NSString stringWithFormat:@"SHOW TABLES FROM %@", dbName];
        theResult = [self queryString:theQuery];
    }
    else {
        NSString	*theQuery = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@ LIKE '%@'", dbName, tablesName];
        theResult = [self queryString:theQuery];
    }
    return theResult;
}


- (MCPResult *)listFieldsFromTable:(NSString *)tableName
/*"
Just a fast wrapper for the more complex list !{listFieldsWithPattern:forTable:} method.
"*/
{
    return [self listFieldsFromTable:tableName like:nil];
}


- (MCPResult *) listFieldsFromTable:(NSString *) tableName like:(NSString *) fieldsName
/*"
Show all the fields of the table tableName which name correspond to pattern (with wild card expansion : %,_).
Indeed, and as recommanded from mysql reference, this method is NOT using mysql_list_fields but the !{queryString:} method.
If an empty string or nil is passed as fieldsName, all fields (of tableName) will be returned.
"*/
{
    MCPResult	*theResult;

    if ((fieldsName == nil) || ([fieldsName isEqualToString:@""])) {
        NSString	*theQuery = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@", tableName];
        theResult = [self queryString:theQuery];
    }
    else {
        NSString	*theQuery = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@ LIKE '%@'", tableName, fieldsName];
        theResult = [self queryString:theQuery];
    }
    return theResult;
}


- (NSString *) clientInfo
/*"
Returns a string giving the client library version.
"*/
{
    return [self stringWithCString:mysql_get_client_info()];
}


- (NSString *) hostInfo
/*"
Returns a string giving information on the host of the DB server.
"*/
{
    return [self stringWithCString:mysql_get_host_info(mConnection)];
}


- (NSString *) serverInfo
/*"
Returns a string giving the server version.
"*/
{
    if (mConnected) {
        return [self stringWithCString: mysql_get_server_info(mConnection)];
    }
    return @"";
}


- (NSNumber *) protoInfo
/*"
Returns the number of the protocole used to transfer info from server to client
"*/
{
    return [MCPNumber numberWithUnsignedInt:mysql_get_proto_info(mConnection)];
}


- (MCPResult *) listProcesses
/*"
Lists active process
"*/
{
    MCPResult	*theResult = [MCPResult alloc];
    MYSQL_RES		*theResPtr;

    if (theResPtr = mysql_list_processes(mConnection)) {
        [theResult initWithResPtr:theResPtr encoding:mEncoding];
    } else {
        [theResult init];
    }

    if (theResult) {
        [theResult autorelease];
    }
    return theResult;
}


/*
- (BOOL)createDBWithName:(NSString *)dbName
{
    const char	*theDBName = [dbName UTF8String];
    if ((mConnected) && (! mysql_create_db(mConnection, theDBName))) {
        return YES;
    }
    return NO;
}

- (BOOL)dropDBWithName:(NSString *)dbName
{
    const char	*theDBName = [dbName UTF8String];
    if ((mConnected) && (! mysql_drop_db(mConnection, theDBName))) {
        return YES;
    }
    return NO;
}
*/


- (BOOL) killProcess:(unsigned long) pid
/*"
Kills the process with the given pid.
The users needs the !{Process_priv} privilege.
"*/
{
    int		theErrorCode;

    theErrorCode = mysql_kill(mConnection, pid);
    return (theErrorCode) ? NO : YES;
}


- (void) disconnect
/*"
Disconnects a connected MCPConnection object; used by !{dealloc:} method.
"*/
{
    if (mConnected) {
        mysql_close(mConnection);
        mConnection = NULL;
    }
    mConnected = NO;
    return;
}

- (void)dealloc
/*"
The standard deallocation method for MCPConnection objects.
"*/
{
    [self disconnect];
    [super dealloc];
    return;
}


- (void) setEncoding:(NSStringEncoding) theEncoding
/*"
Sets the encoding used by the server for data transfert.
Used to make sure the output of the query result is ok even for non-ascii characters
The character set (encoding) used by the db is passed to the MCPConnection object upon connection,
so most likely the encoding (from -encoding) method is already the proper one.
That is to say : It's unlikely you will need to call this method directly, and #{if ever you use it, do it at your own risks}.
"*/
{
    mEncoding = theEncoding;
}


- (NSStringEncoding) encoding
/*"
Gets the encoding for the connection
"*/
{
    return mEncoding;
}


- (const char *) cStringFromString:(NSString *) theString
/*"
For internal use only. Transforms a NSString to a C type string (ending with \0) using the character set from the MCPConnection.
Lossy conversions are enabled.
"*/
{
    NSMutableData	*theData;
    
    if (! theString) {
        return (const char *)NULL;
    }

    theData = [NSMutableData dataWithData:[theString dataUsingEncoding:mEncoding allowLossyConversion:YES]];
    [theData increaseLengthBy:1];
    return (const char *)[theData bytes];
}


- (NSString *) stringWithCString:(const char *) theCString
/*"
Returns a NSString from a C style string encoded with the character set of theMCPConnection.
"*/
{
    NSData		* theData;
    NSString		* theString;

    if (theCString == NULL) {
        return @"";
    }
    theData = [NSData dataWithBytes:theCString length:(strlen(theCString))];
    theString = [[NSString alloc] initWithData:theData encoding:mEncoding];
    if (theString) {
        [theString autorelease];
    }
    return theString;
}


- (NSString *) stringWithText:(NSData *) theTextData
/*"
Use the string encoding to convert the returned NSData to a string (for a Text field)
"*/
{
    NSString		* theString;

    if (theTextData == nil) {
        return nil;
    }
    theString = [[NSString alloc] initWithData:theTextData encoding:mEncoding];
    if (theString) {
        [theString autorelease];
    }
    return theString;
}


@end

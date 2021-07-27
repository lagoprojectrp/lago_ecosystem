#ifndef _MAIN_H_
#define _MAIN_H_

#include <poll.h>
#include <signal.h>
#include <string.h>
#include <time.h>
//#include <fstream>
//#include <iostream>
//#include <vector>

#define _GNU_SOURCE
#include <pthread.h>

#include "zynq_io.h"
#include "gps_rp.h"
#include "bmp180.h"
#include "globaldefs.h"

typedef struct ldata 
{
        int trigg_1;   // trigger level ch1
        int trigg_2;   // trigger level ch2
        int strigg_1;  // sub-trigger level ch1
        int strigg_2;  // sub-trigger level ch2
        int nsamples;  // N of samples
        int time;
        double latitude;
        char lat;
        double longitude;
        char lon;
        uint8_t quality;
        uint8_t satellites;
        double altitude;
} ldata_t;

//*****************************************************
// Pressure, temperature and other constants
//****************************************************
double  gps_lat,gps_lon,gps_alt;

//Globals
int interrupted = 0;
int n_dev;
uint32_t reg_off;
int32_t reg_val;
int histo_nsamples, histo_limit;
int histo_position=0;
//double r_val;
int limit;
int current;
loc_t g_data;
// detector rates
int r1,r2;
// timing horrible hack
int hack=0;

int fReadReg, fGetCfgStatus, fGetPT, fGetGPS, fGetXADC, fInitSystem, fWriteReg, 
		fSetCfgReg, fToFile, fToStdout, fFile, fCount, fByte, fRegValue, fData, 
		fFirstTime=1,	fshowversion, fGetHst;

char charAction[MAXCHRLEN], scRegister[MAXCHRLEN], charReg[MAXCHRLEN],
		 charFile[MAXCHRLEN], charCurrentFile[MAXCHRLEN], charCount[MAXCHRLEN],
		 scByte[MAXCHRLEN], charRegValue[MAXCHRLEN], charCurrentMetaData[MAXCHRLEN];

//FILE        *fhin = NULL;
FILE         *fhout = NULL;
FILE         *fhmtd = NULL;
struct FLContext  *handle = NULL;

#ifdef FUTURE
unordered_map<string, string> hConfigs;
#endif

//****************************************************
// Time globals for filenames
//****************************************************
time_t    fileTime;
struct tm *fileDate;
int       falseGPS=0;

//****************************************************
// Metadata
//****************************************************
// Metadata calculations, dataversion v5 need them
// average rates and deviation per trigger condition
// average baseline and deviation per channel
// using long int as max_rate ~ 50 kHz * 3600 s = 1.8x10^7 ~ 2^(20.5)
// and is even worst for baseline
#define MTD_TRG   8
#define MTD_BL    3
#define MTD_BLBIN 1
//daq time
int mtd_seconds=0;
// trigger rates
long int mtd_rates[MTD_TRG], mtd_rates2[MTD_TRG];
//base lines
long int mtd_bl[MTD_BL], mtd_bl2[MTD_BL];
int mtd_iBin=0;
long int mtd_cbl=0;
// deat time defined as the number of missing pulses over the total number
// of triggers. We can determine missing pulses as the sum of the differences 
// between consecutive pulses
long int mtd_dp = 0, mtd_cdp = 0, mtd_pulse_cnt = 0, mtd_pulse_pnt = 0;
// and finally, a vector of strings to handle configs file. I'm also including a
// hash table
// for future implementations. For now, we just dump the lago-configs file
//vector <string> configs_lines;
int position;
int  main(int argc, char *argv[]);
void signal_handler(int sig);
int  wait_for_interrupt(int fd_int, void *dev_ptr);
void *thread_isr_not_gps(void *p);  
void *thread_isr(void *p);  
void show_usage(char *progname);
void StrcpyS(char *szDst, size_t cchDst, const char *szSrc); 
int  parse_param(int argc, char *argv[]);  
int  new_file(void);
int  read_buffer(int position, void *bmp);

#endif

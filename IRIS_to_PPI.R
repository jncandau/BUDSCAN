library(SBWradar)
library(vol2birdR)
library(terra)
## terraOptions(memmax = 8, memmin = 0.1)
library(ncdf4)

## set command line arguments ----
args <- commandArgs(trailingOnly = TRUE)

#stop the script if no command line argument
if(length(args)==0){
  print("Please include directory of radar data, output directory, clutter file, IRIS (T/F), station name and skip (T/F) as arguments")
  stop("Requires command line argument.")
}

InputDIR <- args[1]
OutputDIR <- args[2]
YMDT <- args[3]
IRIS <- ifelse(args[4] == "T",T,F)
STATION <- args[5]

# Convert IRIS to ODIM
IRIS_to_ODIM(paste0(InputDIR,"/IRIS/"),InputDIR)

a <- pvol_to_stack(paste0(InputDIR,"/",YMDT),OutputDIR,IRIS,STATION)

ppi <- polar_to_ppi(x=a$convol,
                           latitude= 48.4805500879884 ,
                           longitude= -67.6008899509907,                           
			   gate_offset=0,
                           azim_offset=0,
                           gate_step=500,
                           azim_step=0.5,
                           grid_size = 500,
                           range_max = 240000)
 
writeCDF(ppi,filename=paste0(OutputDIR, "/", STATION,
            "_", YMDT, "_ppi_raw.nc"),overwrite=T)


#!/bin/bash

###############################
## Parameters
###############################

if [ "$#" == 4 ]; then
  STATION=$1
  YEAR=$2
  MONTH=$3
  IRIS=$4
else
  echo "Error: The parameters should be: STATION YEAR MONTH IRIS(T/F)"
  exit 1
fi

if [ "$2" -lt 2013 ] || [ "$2" -gt 2025 ]; then
  echo "Error: Second argument should be between 2013 and 2025"
  exit 1
fi

if [ "$3" != "06" ] && [ "$3" != "07" ] && [ "$3" != "08" ] && [ "$3" != "09" ]; then
  echo "Error: Third argument must be 06, 07, 08 or 09."
  exit 1
fi


if [ "$4" != "F" ] && [ "$4" != "T" ]; then
  echo "Error: Fourth argument must be 'T' or 'F'."
  exit 1
fi

# Set working directory
WORK_DIR="/home/jcandau/Radar/BUDSCAN/"

# Set input directory
INPUT_ROOT="/home/jcandau/scratch/Inputs/"

# Set zip file name
filename=$(ls $INPUT_ROOT | grep $YEAR$MONTH | grep -E "${STATION^^}|${STATION}")
ZIP_FILE=${INPUT_ROOT}${filename}

# Check that the input file exists
if [[ ! -f ${ZIP_FILE} ]]; then
   echo "The input file ${ZIP_FILE} is not in the directory ${INPUT_ROOT}"
   exit 0
fi

# Create output directory
OUTPUT_ROOT="/home/jcandau/scratch/BUDSCAN/Inputs/"
OUTPUT_DIR=${OUTPUT_ROOT}${STATION}"_"${YEAR}"/"

# Set skipping or not
SKIP="T"

# Set the filter to collect only parts of June and August and all July
FILTER=${YEAR}${MONTH}

# Calculate number of runs
NRUNS=`unzip -l ~/scratch/Inputs/XAM_201306_volumescan.zip | grep CONVOL | cut -d ":" -f 2 | cut -d " " -f 4 | cut -d "~" -f 1 | sort -n | wc -l`

###############################
# Display 
###############################

echo "#!/bin/bash" > IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --job-name=${STATION}_${YEAR}${MONTH}" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --time=00:05:00" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --mem=16G" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --cpus-per-task=1" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --array=1-${NRUNS}" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH -o /home/jcandau/Radar/BUDSCAN/logs/${STATION}_${YEAR}${MONTH}_%j.out"  >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH -e /home/jcandau/Radar/BUDSCAN/logs/${STATION}_${YEAR}${MONTH}_%j.err"  >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --mail-type=ALL" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "#SBATCH --mail-user=jean.noel.candau@gmail.com" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "module load r/4.5.0 netcdf gdal udunits gsl python/3.9" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "echo \"Running task ID \${SLURM_ARRAY_TASK_ID}\" " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "# Get the Year, Month, Day, Hour and Minute from runfile.txt" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "YMDT=\$(unzip -l ~/scratch/Inputs/${STATION}_${YEAR}${MONTH}_volumescan.zip | grep CONVOL | cut -d \":\" -f 2 | cut -d \" \" -f 4 | cut -d \"~\" -f 1 | sort -n | sed -n \${SLURM_ARRAY_TASK_ID}p)" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh 

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "# Unzip specific input files in TEMP_DIR" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "mkdir \${SLURM_TMPDIR}/IRIS" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "unzip ${ZIP_FILE} \${YMDT}* -d \${SLURM_TMPDIR}/IRIS" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "Rscript IRIS_to_PPI.R \${SLURM_TMPDIR} \${SLURM_TMPDIR} \${YMDT} T XAM" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "cp \${SLURM_TMPDIR}/${STATION}_\${YMDT}_ppi_raw.nc ${OUTPUT_DIR}" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "mkdir \${SLURM_TMPDIR}/PPI" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "mv \${SLURM_TMPDIR}/XAM_\${YMDT}_ppi_raw.nc \${SLURM_TMPDIR}/PPI" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "python3.9 /home/jcandau/software/RadarDetector/detector_batch.py --input \${SLURM_TMPDIR}/PPI --run --output-dir /home/jcandau/scratch/BUDSCAN/Outputs/${STATION}_${YEAR} --mode probability --threshold 0.7"  >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh

echo " " >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh
echo "exit" >> IRIS_to_PPI_${STATION}_${YEAR}${MONTH}.sh


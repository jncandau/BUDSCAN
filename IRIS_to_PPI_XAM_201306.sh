#!/bin/bash
#SBATCH --job-name=XAM_201306
#SBATCH --time=00:05:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=1
#SBATCH --array=1-4206
#SBATCH -o /home/jcandau/Radar/BUDSCAN/logs/XAM_201306_%j.out
#SBATCH -e /home/jcandau/Radar/BUDSCAN/logs/XAM_201306_%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=jean.noel.candau@gmail.com
 
module load r/4.5.0 netcdf gdal udunits gsl python/3.9
 
echo "Running task ID ${SLURM_ARRAY_TASK_ID}" 
 
# Get the Year, Month, Day, Hour and Minute from runfile.txt
YMDT=$(unzip -l ~/scratch/Inputs/XAM_201306_volumescan.zip | grep CONVOL | cut -d ":" -f 2 | cut -d " " -f 4 | cut -d "~" -f 1 | sort -n | sed -n ${SLURM_ARRAY_TASK_ID}p)
 
# Unzip specific input files in TEMP_DIR
mkdir ${SLURM_TMPDIR}/IRIS
unzip /home/jcandau/scratch/Inputs/XAM_201306_volumescan.zip ${YMDT}* -d ${SLURM_TMPDIR}/IRIS
 
Rscript IRIS_to_PPI.R ${SLURM_TMPDIR} ${SLURM_TMPDIR} ${YMDT} T XAM
 
cp ${SLURM_TMPDIR}/XAM_${YMDT}_ppi_raw.nc /home/jcandau/scratch/BUDSCAN/Inputs/XAM_2013/
 
mkdir ${SLURM_TMPDIR}/PPI
mv ${SLURM_TMPDIR}/XAM_${YMDT}_ppi_raw.nc ${SLURM_TMPDIR}/PPI
 
python3.9 /home/jcandau/software/RadarDetector/detector_batch.py --input ${SLURM_TMPDIR}/PPI --run --output-dir /home/jcandau/scratch/BUDSCAN/Outputs/XAM_2013 --mode probability --threshold 0.7
 
exit

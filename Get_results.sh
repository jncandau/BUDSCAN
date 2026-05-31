#!/bin/bash
#SBATCH --job-name=GetResults
#SBATCH --time=01:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=1
#SBATCH --array=1
#SBATCH --mail-type=ALL
#SBATCH --mail-user=jean.noel.candau@gmail.com
 
module load cdo
 
YEAR=$((SLURM_ARRAY_TASK_ID + 2018))

cd /home/jcandau/scratch/BUDSCAN/Outputs/XAM_${YEAR}

for i in $(ls *.nc | cut -d _ -f 2); do echo $i,`cdo -s -output -mulc,100 -fldmean -gtc,0.7 -selname,probability detection_"$i"_probability.nc 2>/dev/null`; done > ~/Radar/BUDSCAN/XAM_${YEAR}_07pct.txt
 
exit

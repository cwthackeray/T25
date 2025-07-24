#!/bin/csh
# ===========================================
# T25 Precipitation & SST Analysis
# ===========================================
# Date: [2025-07-24]
# Description:
#   - Processes ACCESS-ESM1-5 daily precipitation and SST data (adapt for other models/datasets as necessary)
#   - Computes extreme precipitation metrics (99th & 99.9th percentiles)
#   - Calculates heavy precip frequency (>= threshold)
#   - Computes the Oceanic Nino Index (ONI)
# Requirements:
#   - NetCDF data for historical and SSP370 scenarios
# -------------------------------------------
set echo
# ===================
# SETUP
# ===================
set model = "ACCESS-ESM1-5"
set base_dir = "/data/public/gcm/CLIVAR_LE/${model}"
set out_dir = "/work/cwthackeray/models/large_ensembles/${model}"
set sst_dir = "${base_dir}/sst"

# Define ensemble member list (used throughout script)
set members = (r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 \
               r21 r22 r23 r24 r25 r26 r27 r28 r29 r30 r31 r32 r33 r34 r35 r36 r37 r38 r39 r40)

####################
## 1) Data Processing ##
####################
# Loop through ensemble members, concatenate files, convert units of precip to mm/day.

foreach r ($members)
  echo "Processing member ${r}"
  # Go to model directory
  cd $base_dir
  # Historical precipitation (convert from kg/m2/s to mm/day)
  cdo -L setattribute,pr@units=mm/day -mulc,86400 -selvar,pr \
    -cat pr_day_${model}_historical_${r}i1p1f1_gn_19500101-19991231.nc \
         pr_day_${model}_historical_${r}i1p1f1_gn_20000101-20141231.nc \
    ${out_dir}/pr_day_${model}_hist_${r}_1950-2014.mm-day.nc

  # Future precipitation: 2015–2044
  cdo -L setattribute,pr@units=mm/day -mulc,86400 -selvar,pr -selyear,2015/2044 \
    pr_day_${model}_ssp370_${r}i1p1f1_gn_20150101-20641231.nc \
    ${out_dir}/pr_day_${model}_ssp370_${r}_2015-2044.mm-day.nc

  # Future precipitation: 2045–2064
  cdo -L setattribute,pr@units=mm/day -mulc,86400 -selvar,pr -selyear,2045/2064 \
    pr_day_${model}_ssp370_${r}i1p1f1_gn_20150101-20641231.nc \
    ${out_dir}/pr_day_${model}_ssp370_${r}_2045-2064.mm-day.nc

  # Move into SST subdirectory
  cd sst/
  # SST processing (1950–2024, remapped to 1°x1° grid)
  cdo -L selyear,1950/2024 -remapbil,r360x180 \
    -cat tos_Omon_${model}_historical_${r}i1p1f1_gn_185001-201412.nc \
          tos_Omon_${model}_ssp370_${r}i1p1f1_gn_201501-210012.nc \
    ${out_dir}/${model}.${r}.SST.1950-2024.nc
  # Return to base directory before next iteration
  cd $base_dir

end

#################################
## 2) Calculate Precip Metrics ##
#################################

# Percentiles to analyze
foreach pctl (99 99.9)
  # Format: 99 -> 99p, 99.9 -> 999p
  set pcode = `echo $pctl | sed 's/\.//'`p
  foreach r ($members)
    echo "Processing ${r} at p=$pctl"

    # Define core file paths
    set hist_file = ${out_dir}/pr_day_${model}_hist_${r}_1950-2014.mm-day.nc
    set fut1_file = ${out_dir}/pr_day_${model}_ssp370_${r}_2015-2044.mm-day.nc
    set fut2_file = ${out_dir}/pr_day_${model}_ssp370_${r}_2045-2064.mm-day.nc

    # Tmin/tmax for reference period (same for all percentiles)
    cdo -L timmin -selyear,1980/2014 $hist_file ${hist_file}:1980-2014.tmin.nc
    cdo -L timmax -selyear,1980/2014 $hist_file ${hist_file}:1980-2014.tmax.nc

    # Compute historical values for this percentile
    cdo -L timpctl,${pctl} -selyear,1980/2014 $hist_file \
        ${hist_file}:1980-2014.tmin.nc ${hist_file}:1980-2014.tmax.nc ${hist_file}:1980-2014.p${pcode}.nc

    # HIST: calculate annual mean FP≥n
    cdo -L yearmean -ge $hist_file ${hist_file}:1980-2014.p${pcode}.nc \
        ${hist_file}:1950-2014.ge${pcode}.nc
    cdo fldmean ${hist_file}:1950-2014.ge${pcode}.nc \
        ${hist_file}:1950-2014.ge${pcode}.aa.nc

    # FUTURE 2015–2044
    cdo -L yearmean -ge $fut1_file ${hist_file}:1980-2014.p${pcode}.nc \
        ${fut1_file}:2015-2044.ge${pcode}.nc
    cdo fldmean ${fut1_file}:2015-2044.ge${pcode}.nc \
        ${fut1_file}:2015-2044.ge${pcode}.aa.nc

    # FUTURE 2045–2064
    cdo -L yearmean -ge $fut2_file ${hist_file}:1980-2014.p${pcode}.nc \
        ${fut2_file}:2045-2064.ge${pcode}.nc
    cdo fldmean ${fut2_file}:2045-2064.ge${pcode}.nc \
        ${fut2_file}:2045-2064.ge${pcode}.aa.nc

  end
end

### this information can then be output to a csv and read in python for plotting
### for 1979-2024 specific analysis, existing files can be stitched and trimmed
### Zonal means on Figure 2 are computed using cdo zonmean


################################  
## 3) Same as 2 but for monthly means ##
################################

# Loop over members 1–40
foreach r (`seq 1 40`)
  echo "Processing member r$r..."

  set infile = ${out_dir}/pr_day_${model}_ssp370_r${r}_2015-2044.mm-day.nc
  set thresh = ${out_dir}/pr_day_${model}_hist_r${r}.1980-2014.mm-day.p99.nc
  set outfile = ${out_dir}/monthly/pr_day_${model}_ssp370_r${r}_2015-2044.ge99p.mm.aa.nc
  cdo -L fldmean -monmean -ge $infile $thresh $outfile
end

##########################  
# 4) SST Data Processing #
# Calculate Oceanic Nino Index #
##########################

# Loop over all 40 ensemble members
foreach r (`seq 1 40`)

    # Format member label (r1, r2, ..., r40)
    set rname = r${r}
    set infile = ${out_dir}/${model}.${rname}.SST.1950-2024.nc
    set basename = ${model}.${rname}.SST.1950-2024

    echo "Processing file: ${infile}"

    # Step 1: Select Niño 3.4 region (170°W–120°W = 190–240°, 5°S–5°N)
    cdo sellonlatbox,190,240,-5,5 $infile sst_nino34_${basename}.nc

    # Step 2: Detrend SST
    cdo detrend sst_nino34_${basename}.nc sst_nino34_detrended_${basename}.nc

    # Step 3: Monthly climatology over 1981–2010
    cdo -L ymonmean -selyear,1981/2010 sst_nino34_detrended_${basename}.nc \
        climatology_nino34_${basename}.nc

    # Step 4: Anomalies = SST - climatology
    cdo ymonsub sst_nino34_detrended_${basename}.nc climatology_nino34_${basename}.nc \
        sst_anomalies_nino34_${basename}.nc

    # Step 5: Apply 3-month running mean
    cdo runmean,3 sst_anomalies_nino34_${basename}.nc \
        sst_anomalies_nino34_smoothed_${basename}.nc

    # Step 6: Spatial mean to get Niño 3.4 index
    cdo fldmean sst_anomalies_nino34_smoothed_${basename}.nc \
        ${basename}_nino34_index.nc

    # Step 7: Output as text (optional)
    cdo outputtab,value ${basename}_nino34_index.nc > ${basename}_nino34_index.txt

    echo "Saved: ${basename}_nino34_index.nc and .txt"

    # Step 8: Clean up intermediates
    rm sst_nino34_${basename}.nc
    rm sst_nino34_detrended_${basename}.nc
    rm climatology_nino34_${basename}.nc
    rm sst_anomalies_nino34_${basename}.nc
    rm sst_anomalies_nino34_smoothed_${basename}.nc

end

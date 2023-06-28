#!/bin/bash
VERSION=0.0.230626
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

# NOTE: anaconda/miniconda 判別
# NOTE: observed_otus / observed_features 選択


### Contents: Diversity ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義
#  5.3. feature-tableから最小リードデプスを取得
#  5.4. レアファクションカーブ [qiime diversity alpha-rarefaction] 
#  5.5. alpha diversity 比較 & クラスカルウォリス検定 [qiime diversity alpha-group-significance]
#  5.6. Beta diversity [ qiime diversity core-metrics-phylogenetic ]
#  5.7. Beta-diversity per SampleType [qiime diversity beta-group-significance]
#  5.8. PCoAスコアと寄与率、及びalpha-diversityをtsvに変換
#  5.9. Heatmap
###


# 1. ドキュメント
#  1.1. ヘルプの表示 
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <feature-table.qza>
   
説明:
    このプログラムではqiime2のfeature tableと検体のメタデータファイルを入力として、多様性解析を行います。
    オプションとして系統解析データ(rooted-tree.qza)を追加した場合、レアファクションカーブの描画とベータ多様性解析
    オプションとしてtaxonomyデータ(taxonomy.qza)を追加した場合、heatmap
    このプログラムはASVテーブルから各サンプルのリードカウントの総計を計算し、最小リード数を取得します。
    レアファクションカーブを描画する場合、最小リード数を指定する必要があり、ASVテーブルから最小リード数を取得します。
    またメタデータファイルをオプションで指定指定することも可能です。

    # 01_alpha-rarefaction
    # 02_Kruskal-wallis test of alpha-diversity
    # 03_PCoA plots of beta diversity 
    # 04_heatmap_with_HCA

    qiime diversity alpha-rarefaction
    qiime diversity alpha
    qiime diversity alpha-group-significance adjusted p-value of Benjamini & Hochberg correction.
    qiime diversity core-metrics-phylogenetic
    qiime diversity beta-group-significance
    qiime feature-table filter-features
    qiime taxa collapse
    qiime feature-table heatmap

オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -m    メタデータファイル[default: map.txt]
  -r    rooted-tree.qza
  -x    taxonomy.qza
  -h    ヘルプドキュメントの表示

EOS
}

#  1.2. 使用例の表示
function print_usg() {
cat << EOS >&2
使用例:
  $CMDNAME -m map.txt -r rooted-tree.qza -x taxonomy.qza table.qza 

EOS
}

# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:m:r:x:h OPT
do
  case $OPT in
    "e" ) VALUE_e="$OPTARG";;
    "q" ) VALUE_q="$OPTARG";;    
    "m" ) VALUE_m="$OPTARG";;
    "r" ) VALUE_r="$OPTARG";;    
    "x" ) VALUE_x="$OPTARG";;
    "h" ) print_doc
            exit 1 ;; 
    *) print_doc
        exit 1;; 
    \? ) print_doc
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

## conda環境変数ファイルの存在確認
if [[ -z "$VALUE_e" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; else CENV=${VALUE_e}; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi

## qiime2環境の存在確認
if [[ -z "$VALUE_q" ]]; then QENV="qiime2-2022.2"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] There is no ${QENV} environment."
    conda info --envs
    print_usg
    exit 1
fi

#  2.2. オプション引数の判定およびデフォルト値の指定
## Metadata
if [[ -z "$VALUE_m" ]]; then META='map.txt'; else META=${VALUE_m}; fi
if [[ -f "${META}" ]]; then
  NST=$((`cat ${META} | awk -F"\t" 'NR==1{print NF}' `-1))
else 
  echo -e "[ERROR] There is not meta-data file."
  exit 1
fi

## TREE
if [[ -z "$VALUE_r" ]]; then TRE='rooted-tree.qza'; else TRE=${VALUE_r}; fi
if [[ ! -f "${TRE}" ]] ; then echo "[ERROR] The ${TRE} could not find." ; exit 1; fi

## TAXONOMY
if [[ -z "$VALUE_x" ]]; then TAX='taxonomy.qza'; else TAX=${VALUE_x}; fi
if [[ ! -f "${TAX}" ]] ; then echo "[ERROR] The ${TRE} could not find." ; exit 1; fi

# 3. コマンドライン引数の処理
if [ "$#" = 0 ]; then
  print_usg
  exit 1
elif [[ "$#" = 1 && -f $1 ]] ; then
  TAB=$1 
else
  echo "[ERROR] The input file could not find, or ."
fi

## その他引数初期値
OUTV='diversity_qzv' 
OUTA='diversity_qza'
OUTT='diversity_tsv'
OUTAST="${OUTV}/alpha-rarefaction_SampleType.qzv"
OUTASD="${OUTV}/alpha-rarefaction_SampleID.qzv"
ALP=(chao1 simpson shannon)


# 4. プログラムに渡す引数の一覧 
cat << EOS >&2
### Diversity analysis ###
  conda environmental variables : [ ${CENV} ]
  qiime2 environment :            [ ${QENV} ]
  count table:                    [ $TAB ]
  rooted tree:                    [ $TRE ]
  taxonomy:                       [ $TAX ]
  metadata:                       [ $META ]
  sample type:                    [ $NST ]
  alpha-diversity metrics:        [ ${ALP[*]} ]

  output rarefaction sampletype:  [ ${OUTAST} ]
  output rarefaction sampleID:    [ ${OUTASD} ]

  output diversity analysis qzv:  [ ${OUTV} ]
  output diversity analysis qza:  [ ${OUTA} ]
  output diversity analysis qza:  [ ${OUTT} ]

EOS

# Saved FeatureTable[Frequency] to: Beta_diversity/rarefied_table.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/faith_pd_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/observed_features_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/shannon_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/evenness_vector.qza

# Saved DistanceMatrix to: Beta_diversity/unweighted_unifrac_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/weighted_unifrac_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/jaccard_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/bray_curtis_distance_matrix.qza

# Saved PCoAResults to: Beta_diversity/unweighted_unifrac_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/weighted_unifrac_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/jaccard_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/bray_curtis_pcoa_results.qza

# Saved Visualization to: Beta_diversity/unweighted_unifrac_emperor.qzv
# Saved Visualization to: Beta_diversity/weighted_unifrac_emperor.qzv
# Saved Visualization to: Beta_diversity/jaccard_emperor.qzv
# Saved Visualization to: Beta_diversity/bray_curtis_emperor.qzv

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

#  5.2. 関数定義

#  5.3. feature-tableから最小リードデプスを取得
## unzip table.qza & convert feature table to tsv
 unzip -q ${TAB} -d dat
 biom convert -i dat/*/data/feature-table.biom -o ./feature-table.tsv --to-tsv
 rm -r dat
## get minimum depth value from feature table
 DP=$(cat feature-table.tsv \
 | awk -F"\t" '!/^#/{for(i=1;i<NF; i++)sum[i]+=$(i+1)}/^#OTU/{for(i=1; i<NF; i++) hd[i]=$(i+1)} \
  END{for(i=1;i<=length(sum);i++)print hd[i]":"sum[i]}')

## results
 MINDP=$(echo ${DP[*]} | tr ' ' '\n' | cut -f2 -d":" | sort -n | head -1)
 echo -e "### Check read depth ###"
 echo ${DP[@]} | tr ' ' '\n' 
 echo "Minimum depth: ${MINDP}" > mindp.txt
 rm feature-table.tsv

#  5.4. レアファクションカーブ [qiime diversity alpha-rarefaction] 
## NOTE: observed_features / faith_pd  : はalpha diversityは出さないのか? 
echo -e "### qiime diversity alpha-rarefaction ### "
## arguments check: 出力ディレクトリ
if [[ -d "${OUTA}" ]]; then echo "[WARNING] ${OUTA} was already exists. The output files may be overwritten." ; else mkdir -p "${OUTA}"; fi 
if [[ -d "${OUTV}" ]]; then echo "[WARNING] ${OUTV} was already exists. The output files may be overwritten." ; else mkdir -p "${OUTV}"; fi 
## arguments check: 出力ファイル 
 if [[ -f "${OUTAST}" ]] ; then echo "[WARNING] 既存のalpha-rarefaction_SampleType.qzvは上書きされます"; fi
 if [[ -f "${OUTASD}" ]] ; then echo "[WARNING] 既存のalpha-rarefaction_SampleID.qzvは上書きされます"; fi

## alpha rarfaction (observed_otus -> observed_features)
if [[ -f "${META}" ]] ; then
 ## rarefaction with metadata
  echo -e "[INFO] 'qiime diversity alpha-rarefaction' with meta data."
  qiime diversity alpha-rarefaction \
  --i-table ${TAB} \
  --i-phylogeny ${TRE} \
  --p-max-depth ${MINDP} \
  --p-metrics simpson \
  --p-metrics shannon \
  --p-metrics observed_features \
  --p-metrics faith_pd \
  --p-metrics chao1 \
  --m-metadata-file ${META} \
  --o-visualization ${OUTAST}
 ## rarefaction withouut metadata
  echo -e "[INFO] 'qiime diversity alpha-rarefaction' without meta data."
  qiime diversity alpha-rarefaction \
  --i-table ${TAB} \
  --i-phylogeny ${TRE} \
  --p-max-depth ${MINDP} \
  --p-metrics simpson \
  --p-metrics shannon \
  --p-metrics observed_features \
  --p-metrics faith_pd \
  --p-metrics chao1 \
  --o-visualization ${OUTASD}

else 
 ## rarefaction withouut metadata
  echo -e "[INFO] 'qiime diversity alpha-rarefaction' without meta data."
  qiime diversity alpha-rarefaction \
  --i-table ${TAB} \
  --i-phylogeny ${TRE} \
  --p-max-depth ${MINDP} \
  --p-metrics simpson \
  --p-metrics shannon \
  --p-metrics observed_features \
  --p-metrics faith_pd \
  --p-metrics chao1 \
  --o-visualization ${OUTASD}

fi

## 出力ファイルがなければ終了
if [[ ! -f "${OUTAST}" || ! -f "${OUTASD}" ]]; then  echo "[ERROR] レアファクションカーブは描画されませんでした。" ; exit 1 ; fi

#  5.5. alpha diversity 比較 & クラスカルウォリス検定 [qiime diversity alpha-group-significance]
## NOTE: qzvのファイル名変更すべき vectorじゃない。　${i}_significance.qzv
echo -e "### qiime diversity alpha ### "
for i in ${ALP[@]}; do
## arguments 
  va="${OUTA}/${i}_vector.qza"
  vz="${OUTV}/${i}_vector.qzv"
  echo -e "[INFO] alpha-diversity measure | alpha-diversity | alpha-group-significance   [ ${i} | ${va} | ${vz} ]"
## alpha diversity
  qiime diversity alpha \
  --i-table ${TAB} \
  --p-metric ${i} \
  --o-alpha-diversity ${va}

## alpha diversity significance
  qiime diversity alpha-group-significance \
  --i-alpha-diversity ${va} \
  --m-metadata-file ${META} \
  --o-visualization ${vz}

done

## 出力ファイルがなければ終了
if [[ ! -f "${va}" || ! -f "${vz}" ]]; then  echo "[ERROR] クラスカルウォリス検定は描画されませんでした。" ; exit 1 ; fi

#  5.6. Beta diversity [ qiime diversity core-metrics-phylogenetic ]
## NOTE: --output-dirがすでにある場合エラー, 個別に出力指定
 echo -e "### qiime diversity core-metrics-phylogenetic ### " 
 qiime diversity core-metrics-phylogenetic \
 --i-phylogeny ${TRE} \
 --i-table ${TAB} \
 --m-metadata-file ${META} \
 --p-sampling-depth ${MINDP} \
 --o-rarefied-table ${OUTA}/rarefied_table.qza \
 --o-faith-pd-vector ${OUTA}/faith_pd_vector.qza \
 --o-observed-features-vector ${OUTA}/observed_features_vector.qza \
 --o-shannon-vector ${OUTA}/shannon_vector.qza \
 --o-evenness-vector ${OUTA}/evenness_vector.qza \
  --o-unweighted-unifrac-distance-matrix ${OUTA}/unweighted_unifrac_distance_matrix.qza \
  --o-weighted-unifrac-distance-matrix ${OUTA}/weighted_unifrac_distance_matrix.qza \
  --o-jaccard-distance-matrix ${OUTA}/jaccard_distance_matrix.qza \
  --o-bray-curtis-distance-matrix ${OUTA}/bray_curtis_distance_matrix.qza \
  --o-unweighted-unifrac-pcoa-results ${OUTA}/unweighted_unifrac_pcoa_results.qza \
  --o-weighted-unifrac-pcoa-results ${OUTA}/weighted_unifrac_pcoa_results.qza \
  --o-jaccard-pcoa-results ${OUTA}/jaccard_pcoa_results.qza \
 --o-bray-curtis-pcoa-results ${OUTA}/bray_curtis_pcoa_results.qza \
 --o-unweighted-unifrac-emperor ${OUTV}/unweighted_unifrac_emperor.qzv \
 --o-weighted-unifrac-emperor ${OUTV}/weighted_unifrac_emperor.qzv \
 --o-jaccard-emperor ${OUTV}/jaccard_emperor.qzv \
 --o-bray-curtis-emperor ${OUTV}/bray_curtis_emperor.qzv

 echo "[INFO] Results of core-metrics-phylogenetic qza"; ls ${OUTA}/*.qza | tr ' ' '\n' 
 echo "[INFO] Results of core-metrics-phylogenetic qzv"; ls ${OUTV}/*.qzv | tr ' ' '\n'

#  5.7. Beta-diversity per SampleType [qiime diversity beta-group-significance]
 echo -e "### qiime diversity beta-group-significance ### "
## arguments
 BDMATS=(unweighted_unifrac_distance_matrix.qza weighted_unifrac_distance_matrix.qza bray_curtis_distance_matrix.qza)
 st=(`seq 1 $NST`)
## beta-group-significance
for bd in ${BDMATS[@]}; do
  INMAT=${OUTA}/${bd}
  for j in ${st[@]}; do
    METACL=$(head -1 ${META} | cut -f"$(($j+1))")
    OUTBSV=`echo ${OUTV}/${bd/_distance_matrix.qza/}_anosim_${METACL}.qzv`

    # Input/Output
    echo -e "[INFO] Distance measure | Column_of_Metadata | Output of beta-group-significance\n\t[ ${bd} | ${METACL} | ${OUTBSV} ]"

    ## beta-group-significance
    qiime diversity beta-group-significance  \
    --i-distance-matrix ${INMAT} \
    --m-metadata-file ${META} \
    --m-metadata-column ${METACL} \
    --p-method anosim \
    --p-pairwise \
    --o-visualization ${OUTBSV}        
  done    
done

#  5.8.  Export tsv
function unqza_div () {
  # unzip -> data path -> extract data_frame -> exporeted_dirに保存
  # USAGE: unqza_div diversity_tsv $SHN $CHA $SMP $PCOU $PCOW $PCOB
  EXPORTD=$1; SHN=$2; CHA=$3; SMP=$4; PCOU=$5; PCOW=$6; PCOB=$7

  TEMP_SHN=$(mktemp -d)
  TEMP_CHA=$(mktemp -d)
  TEMP_SMP=$(mktemp -d)
  TEMP_PCOU=$(mktemp -d)
  TEMP_PCOW=$(mktemp -d)
  TEMP_PCOB=$(mktemp -d)
  trap "rm -rf $TEMP_SHN $TEMP_CHA $TEMP_SMP $TEMP_PCOU $TEMP_PCOW $TEMP_PCOB" EXIT

  unzip -q $SHN -d ${TEMP_SHN}
  unzip -q $CHA -d ${TEMP_CHA}
  unzip -q $SMP -d ${TEMP_SMP}
  unzip -q $PCOU -d ${TEMP_PCOU}
  unzip -q $PCOW -d ${TEMP_PCOW}
  unzip -q $PCOB -d ${TEMP_PCOB}

  cp ${TEMP_SHN}/*/data/alpha-diversity.tsv ${EXPORTD}/shannon_vector.tsv
  cp ${TEMP_CHA}/*/data/alpha-diversity.tsv ${EXPORTD}/chao1_vector.tsv
  cp ${TEMP_SMP}/*/data/alpha-diversity.tsv ${EXPORTD}/simpson_vector.tsv

  # data frame extraction from PCoA results
  PCOUDAT=$TEMP_PCOU/*/data/ordination.txt
  cat $PCOUDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/unweighted_unifrac_pcoa_results.tsv
  cat $PCOUDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/unweighted_unifrac_pcoa_pe.txt

  PCOWDAT=$TEMP_PCOW/*/data/ordination.txt
  cat $PCOWDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/weighted_unifrac_pcoa_results.tsv
  cat $PCOWDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/weighted_unifrac_pcoa_pe.txt

  PCOBDAT=$TEMP_PCOB/*/data/ordination.txt
  cat $PCOBDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/bray_curtis_pcoa_results.tsv 
  cat $PCOBDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/bray_curtis_pcoa_pe.txt

}
SHN=${OUTA}/shannon_vector.qza
CHA=${OUTA}/chao1_vector.qza
SMP=${OUTA}/simpson_vector.qza
PCOU=${OUTA}/unweighted_unifrac_pcoa_results.qza
PCOW=${OUTA}/weighted_unifrac_pcoa_results.qza
PCOB=${OUTA}/bray_curtis_pcoa_results.qza

mkdir -p ${OUTT}
unqza_div ${OUTT} $SHN $CHA $SMP $PCOU $PCOW $PCOB

#  5.9. HeatMap
## biom形式のfeature table    qiime feature-table filter-features
echo -e "[INFO] qiime feature-table filter-features"
qiime feature-table filter-features \
--i-table ${TAB} \
--m-metadata-file ${TAX} \
--o-filtered-table ${OUTA}/id-filtered-table.qza

## Heatmap with sample type
echo -e "### qiime taxa collapse & qiime feature-table heatmap ###"
## arguments
LEV=(2 3 4 5 6 7)
clm='ward'
st=(`seq 1 $NST`)

## heat map with metadata for all taxonomic rank
for i in ${LEV[@]}; do 
  out="${OUTA}/table-l${i}.qza" 
  echo -e "[INFO] Input | Output\t[ id-filtered-table.qza | ${out} ]"

  qiime taxa collapse \
  --i-table ${OUTA}/id-filtered-table.qza \
  --i-taxonomy ${TAX} \
  --p-level ${i} \
  --o-collapsed-table ${out}

  for j in ${st[@]}; do
    outheat="${OUTV}/heatmap_l${i}_SampleType${j}.qzv"
    METACL=$(head -1 ${META} | cut -f"$(($j+1))")
    echo -e "[INFO] Input | Sample_type | Output\t[${out} | ${METACL} | ${outheat} ]"
    
      qiime feature-table heatmap \
      --i-table ${out}  \
      --m-sample-metadata-file ${META} \
      --m-sample-metadata-column ${METACL} \
      --o-visualization ${outheat} \
      --p-normalize \
      --p-method ${clm} \
      --p-color-scheme RdYlBu_r
  done    
done

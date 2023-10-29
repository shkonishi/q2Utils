#!/bin/bash
VERSION=0.0.231025
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### Contents: Merge taxonomy and feature table ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定およびデフォルト値の指定
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義 
#  5.3. qza ファイルを一時ディレクトリに展開
#  5.4. 出力ディレクトリ及び一時ディレクトリ作成
#  5.5. ASVのラベル変更
#  5.6. feature-tableのフィルタリング
#  5.7. フィルタ後のASV, feature-table, taxonomyをqzaに変換
#  5.8. taxonomyとfeature-tableをマージ
#  5.9. taxonomy rankごとに集計
###


# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <taxonomy.qza> 

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV配列          Denoisingされた配列 [repset.qza]
    feature-table   検体に含まれるASVのリードカウントテーブル. [table.qza]
    taxonomy        ASVの系統推定結果 qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表        taxonomyデータとfeature-tableを結合したもの [taxonomy_cnt.tsv]

説明:
    このプログラムではqiime2が出力したfeature-table, taxonomy, 及びASV配列を以下のように編集します。
      - ASVのラベル変更
      - feature-table、taxonomy及びASV配列を最大リード数でフィルタリング
      - フィルタリング後のfeature-tableとtaxonomyをマージ
      - 分類階層ごとのカウントテーブルに要約

    入力ファイルはコマンドライン引数にtaxonomyデータ[taxonomy.qza]を指定し、
    オプション引数としてfeature-table[table.qza]及びASV配列[repset.qza]の両方を指定してください。
    いずれもqza形式で指定します。編集後の出力ファイルは全てtsv形式で出力フォルダに書き出されます。

オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -t    feature-table [default: table.qza]
  -s    ASV配列 [default: repset.qza]
  -n    feature-tableとASV配列から、最大読み取り回数がn回以下の配列を削除 [default: 0 ] 
        qiime feature-table filter-featuresは使用していない
  -o    出力ディレクトリ名[default: Results]
  -p    出力ファイルプレフィックス[default: otu]
  -h    ヘルプドキュメントの表示
EOS
}
#  1.2. 使用例の表示
function print_usg() {
cat << EOS
使用例: 
    $CMDNAME -t table.qza -s repset.qza taxonomy.qza         # ASV及びfeature-tableとtaxonomyを結合
    $CMDNAME -n 3 -t table.qza -s repset.qza taxonomy.qza    # ASV及びfeature-tableのフィルタリング. 最大3カウントのASV除外

    CENV=\${HOME}/miniconda3/etc/profile.d/conda.sh
    QENV='qiime2-2021.8'
    $CMDNAME -e \$CENV -q \$QENV  -n 3 -o Results -p otu -t table.qza -s repset.qza taxonomy.qza

EOS
}
# 1.2. エラー
function print_err () { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]:$*" >&2 ;  }


# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:t:s:n:o:p:uvh OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "t" ) VALUE_t="$OPTARG";;
    "s" ) VALUE_s="$OPTARG";;
    "n" ) VALUE_n="$OPTARG" ;;
    "o" ) VALUE_o="$OPTARG";;
    "p" ) VALUE_p="$OPTARG";;
    "u" ) FLG_u="TRUE" ;;
    "v" ) echo $VERSION; exit 1 ;;
    "h" ) print_doc ; print_usg ; exit 1 ;; 
    *)    print_doc ; exit 1;; 
    \? )  print_doc ; print_usg ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

#  2.2. オプション引数の判定およびデフォルト値の指定
## conda環境変数ファイルの存在確認
if [[ -z "${CENV}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 print_err "[ERROR] The file for the conda environment variable cannot be found. ${CENV}" 
 print_usg
 exit 1
fi
## qiime2環境の存在確認
if [[ -z "${QENV}" ]]; then QENV="qiime2-2022.2"; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
  :
else 
  print_err "[ERROR] The conda environment ${QENV} was not found." >&2 
  conda info --envs
  print_usg
  exit 1
fi

## ASV配列, feature-tableの判定
if [[ -z "${VALUE_s}" || -z "${VALUE_t}" ]]; then print_err "[ERROR] Both options t/s must be selected."; exit 1 ; fi
if [[ -n "${VALUE_s}" && -n "${VALUE_t}" ]]; then
  SEQ=${VALUE_s} ; TAB=${VALUE_t}
  if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then 
      print_err "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format."  ; exit 1
  fi  
  if [[ ! -f ${TAB} || ${TAB##*.} != 'qza' ]] ; then 
      print_err "[ERROR] The ASV table ${TAB} does not exist or is not in qza format." ; exit 1
  fi
fi

## その他オプション引数の判定とデフォルト値
### Filter with read-depth
if [[ -z "${VALUE_n}" ]]; then 
  DP=0
elif [[ -n "${VALUE_n}" && "${VALUE_n}" =~ ^[0-9]+$  ]]; then
  DP=${VALUE_n}
else 
  print_err "[ERROR] ${VALUE_n} is not number" ; exit 1
fi
### Results directory
if [[ -n "${VALUE_o}" && -d "${VALUE_o}" ]]; then 
  print_err "[ERROR] The ${VALUE_o} already exist."; exit 1
elif [[ -n "${VALUE_o}" && ! -d "${VALUE_o}" ]]; then
  OUTD=${VALUE_o}
elif [[ -z ${VALUE_o} ]]; then
  OUTD='./Results' 
fi

## Output files
if [[ -z "${VALUE_p}" ]];then PFX='otu' ; else PFX=${VALUE_p} ; fi
OTT=${OUTD}/${PFX}_filtered_cnt.tsv
RTT=${OUTD}/${PFX}_removed_cnt.tsv 
OTTZ=${OUTD}/${PFX}_filtered_cnt.qza

OTF=${OUTD}/${PFX}_filtered_asv.tsv 
RTF=${OUTD}/${PFX}_removed_asv.tsv
OTFA=${OUTD}/${PFX}_filtered_asv.fasta
OTFAZ=${OUTD}/${PFX}_filtered_asv.qza

OTX=${OUTD}/${PFX}_filtered_tax.tsv
RTX=${OUTD}/${PFX}_removed_tax.tsv
OTXZ=${OUTD}/${PFX}_filtered_tax.qza

MTT=${OUTD}/${PFX}_merged_cnt.tsv

# 3. コマンドライン引数の処理 
if [[ "$#" = 0 ]]; then 
  print_doc; print_usg; exit 1 
elif [[ $# = 1 ]] ; then
  TAX=$1
  if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then 
      print_err "[ERROR] The taxonomy data ${TAX} does not exist or is not in qza format." ; exit 1
  fi
else
    print_err "[ERROR] Taxonomy data (qza format) is required as a command line argument." ;  print_usg ; exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Merge taxonomy into count data, ASV sequences, and ASV trees ###
  conda environmental values :              [ ${CENV} ]
  qiime2 environment :                      [ ${QENV} ]
  Input taxonomy file path:                 [ ${TAX} ]
  Input ASV table file path:                [ ${TAB} ]
  Input ASV file path:                      [ ${SEQ} ]
  A maximum read count of remove            [ ${DP} ]
  Output directory:                         [ ${OUTD} ]
  
  Output filtered count table:              [ ${OTT} ]
  Output removed taxonomy table:            [ ${RTT} ]
  Output filtered count table(qza):         [ ${OTTZ} ]

  Output filtered ASV sequence table:       [ ${OTF} ]
  Output filtered ASV sequence fasta(qza):  [ ${OTFAZ} ]
  Output removed ASV sequence table:        [ ${RTF} ]

  Output filtered taxonomy table:           [ ${OTX} ]
  Output filtered taxonomy table(qza):      [ ${OTXZ} ]  
  Output removed taxonomy table:            [ ${RTX} ]

  Output merged count table:                [ ${MTT} ]
  
EOS

# 5. 系統組成表の編集
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then 
 source activate ${QENV}
else 
 conda activate ${QENV} 
fi

# 5.2. 関数定義 
## 5.2.1. 関数定義: qzaファイルの展開
function unqza () {
  local TTAX=$1; local TTAB=$2 ; local TSEQ=$3
  TEMP_TAX=$(mktemp -d)
  TEMP_TAB=$(mktemp -d)
  TEMP_SEQ=$(mktemp -d)
  trap "rm -rf ${TEMP_TAX} ${TEMP_TAB} ${TEMP_SEQ}" EXIT

  # output directory
  OUTT='exported_txt'; 
  if [[ -d "${OUTT}" ]];then
      echo -e "[WARNING] ${OUTT} already exists. The output files may be overwritten." >&2
  else 
      mkdir -p "${OUTT}"
  fi
  
  unzip -q ${TTAX} -d $TEMP_TAX
  TAXTSV="${TEMP_TAX}/*/data/taxonomy.tsv"
  if [[ ! -f $(echo $TAXTSV) ]] ; then 
      echo -e "[ERROR] The specified argument ${TTAX} may not be a taxonomy." >&2
      exit 1 
  else 
      echo -e "[INFO] The taxonomy data unzipped to temporary directory.  ${TAXTSV}" >&2
      mv ${TAXTSV} ${OUTT}
  fi

  unzip -q ${TTAB} -d ${TEMP_TAB}
  BIOME="${TEMP_TAB}/*/data/feature-table.biom" 
  FTTSV=${TEMP_TAB}/feature-table.tsv
  biom convert -i ${BIOME} -o ${FTTSV} --to-tsv 
  if [[ ! -f $(echo ${BIOME}) ]] ; then
      echo -e "[ERROR] ${TAB} may not be a feature table. " >&2
      exit 1
  else 
    echo -e "[INFO] The feature table data unzipped to temporary directory.  ${BIOME}" >&2
    echo -e "[INFO] The feature table data as biom convert to tsv.  ${FTTSV} " >&2
    mv ${FTTSV} ${OUTT}
  fi  

  unzip -q ${TSEQ} -d ${TEMP_SEQ} 
  ASVFA="${TEMP_SEQ}/*/data/dna-sequences.fasta" 
  if [[ ! -f $(echo ${ASVFA}) ]] ; then
    echo -e "[ERROR] ${SEQ} may not be a ASV fasta. " >&2
    exit 1
  else 
    echo -e "[INFO] The ASV fasta unzipped to temporary directory.  ${ASVFA}" >&2
    mv ${ASVFA} ${OUTT}
  fi 

}

# 5.2.2. 関数定義: relabel 
function relabel () {
  local CNT=$1 ; local ASV=$2 ; local TAX=$3; local RLCNT=$4 ; local RLASV=$5; local RLTAX=$6
  # ASVのハッシュ値とOTUの対応表. この段階でASV_IDの同一性の確認は取れているものとする
  cut -f1 ${CNT} | awk 'NR>2{print $1"\t" "OTU" NR-2}' > asv2otu.tsv
  ls asv2otu.tsv > /dev/null 2>&1 || { echo -e "[ERROR] There is not ASV_ID corresponding table." >&2 ; }

  # ラベル置換
  head -2 ${CNT} | tail -1  > ${RLCNT}
  echo -e "OTU_ID\tSeq"> ${RLASV}
  head -1 ${TAX} > ${RLTAX}
  paste asv2otu.tsv <(awk 'NR>2' ${CNT}) | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLCNT}
  paste asv2otu.tsv <(cat ${ASV} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') \
  | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLASV}
  paste asv2otu.tsv <(awk 'NR>1' ${TAX})  | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLTAX}
  # 列数Check

}

# 5.2.3. 関数定義: Filter
function filterOtu () {
  #　リード深度によるフィルタリング, -d 0 [DP=0]を指定した場合、
  local DP=$1; local RLCNT=$2; local RLASV=$3; local RLTAX=$4
  local PICKCNT=$5; local RMCNT=$6; local PICKASV=$7; local RMASV=$8; local PICKTAX=$9; local RMTAX=${10}

  # echo $DP; echo $CNT; echo $ASV ; echo $TAX 
  # echo $PICKCNT; echo $RMCNT; echo $PICKASV; echo $RMASV; echo $PICKTAX; echo $RMTAX

  if [[ ${DP} > 1 ]]; then
    ## 最大リード数以下のOTUのIDを取得(ヘッダ行があることに注意)
    PICKOTU=($(cat ${RLCNT} \
    | awk -F"\t" -v DP=${DP} 'NR>1{for(i=2;i<=NF;i++){if(max[NR]==0){max[NR]=$i}else if(max[NR]<$i){max[NR]=$i}};if( max[NR]>DP)print $1;}' ))
    echo "[INFO] Pick ${#PICKOTU[@]} otu in $(($(cat ${RLCNT} | wc -l)-1)) " >&2

    ## フィルターパスしたカウントテーブルと除去したカウントテーブルを別々に保存
    head -1 ${RLCNT} > ${PICKCNT}
    head -1 ${RLCNT} > ${RMCNT}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKCNT}'"; else print >> "'${RMCNT}'" }' \
      <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
      <( awk -F"\t" 'NR>1' ${RLCNT} )

    ## フィルターパスしたASVと除去したASVを別々に保存
    head -1 ${RLASV} > ${PICKASV}
    head -1 ${RLASV} > ${RMASV}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKASV}'"; else print >> "'${RMASV}'"}' \
    <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
    <( awk -F"\t" 'NR>1' ${RLASV} ) 

    ## フィルターパスしたtaxonomyと除去したtaxonomyを別々に保存
    head -1 ${RLTAX} > ${PICKTAX}
    head -1 ${RLTAX} > ${RMTAX}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKTAX}'"; else print >> "'${RMTAX}'"}' \
    <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
    <( awk -F"\t" 'NR>1' ${RLTAX} ) 

  else
    mv ${RLCNT} ${PICKCNT}
    mv ${RLASV} ${PICKASV}
    mv ${RLTAX} ${PICKTAX}
  fi
}

## 5.2.4. 関数定義: Combine taxonomy and feature-table <stdout>
function mtax () {
  # NOTE: feature-tableにはコメント行が2行存在、ただし最終行末尾に改行コードがないので行数はtaxonomyと一緒になっている
  # NOTE: ただしこのスクリプト内ではlabel変更の再にfeature-tableの1行目(# Constructed from biom file)は消去済み
  # NOTE: taxonomyとfeature-tableをpasteで結合した後にIDが同じことを確認してプリント,ID列をcutで除去
  # NOTE: PR2ではtaxonomy rank が8存在するので場合分けが必要
  local TTAX=$1; local TTAB=$2 ; local MTAB=$3

  # idの同一性チェック
  id_tab=($(grep -v "^#" ${TTAB} | awk -F"\t" '{print $1}'))
  id_tax=($(grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'))
  un1=($(echo ${id_tab[*]} ${id_tax[*]} | tr ' ' '\n' | sort | uniq -u))
  if [[ ${#un1} != '0' ]]; then echo "[ERROR] The file format of inputs was invalid. $1 and/or $2" >&2 ; fi

  # カウントデータからヘッダ行抽出
  if head -1 ${TTAB} | grep -e "^# Constructed from biom file$" > /dev/null ; then 
    HDTAB=($(tail +2 ${TTAB} | head -1 | cut -f2-))
  elif head -1 ${TTAB} | grep -e "^#OTU ID" > /dev/null ; then 
    HDTAB=($(grep -e "^#OTU ID" ${TTAB} | head -1 | cut -f2-))
  fi

  # taxonomyデータから分類階層のヘッダ行抽出 (7もしくは8の場合がある, また全てのOTUのrankが7もしくは8階層とは限らない)
  RANK=($(cut -f2 ${TTAX} | awk -F"; " 'BEGIN{OFS="\t"}NR>1{for(i=1;i<=NF;i++){sub("__.*$", "", $i)};print }' | sort | uniq | tail -1))
  NRANK=${#RANK[@]}
  HDC=($(echo 'OTU_ID' 'Confidence' ${RANK[@]} ${HDTAB[@]}))

  # ランク毎のテーブルに整形、未分類のセルには空文字を入れる(そのままだとカラム数が揃わない)
  if [[ $NRANK == '7' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MTAB
    paste <(tail +2 $TTAX | cut -f1,3) \
    <(tail +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
    <(grep -v "^#" ${TTAB}) | awk -F"\t" '$1==$10' | cut -f1-9,11- >> $MTAB
  elif [[ $NRANK == '8' ]]; then
    echo ${HDC[@]} | tr ' ' '\t'
    paste <(tail +2 $TTAX | cut -f1,3) \
    <(tail +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}') \
    <(grep -v "^#" ${TTAB}) | awk -F"\t" '$1==$11' | cut -f1-10,12- >> $MTAB
  else 
    echo -e "[ERROR] The file format of inputs was invalid." >&2
  fi

  # 出力ファイルチェック
  out_ncol=($(cat $MTAB | awk -F"\t" '{print NF}' | uniq)) 
  out_wl=$(cat $MTAB | wc -l); tax_wl=$(cat $TTAX | wc -l) ; tab_wl=$(cat $TTAB | wc -l)
  if [[ ${#out_ncol[@]} != '1' ]]; then 
    echo -e "[ERROR] The file format of inputs was invalid."  >&2
  fi
  if [[ ${out_wl} != ${tax_wl} || ${out_wl} != ${tab_wl} || ${tax_wl} != ${tab_wl} ]]; then
    echo -e "[ERROR] The output files format of inputs was invalid." >&2   
  fi  

}
## 5.2.5. 関数定義: Combine taxonomy and ASV <stdout>
function mtseq () {
  local TTAX=$1; local TSEQ=$2; local MSEQ=$3

  # idの同一性チェック
  id_seq=($(grep "^>" ${TSEQ} | sed 's/^>//'))
  id_tax=($(grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'))
  un1=($(echo ${id_tax[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -u)) 
  if [[ ${#un1} != '0' ]]; then echo "[ERROR] The file format of inputs was invalid. $1 and/or $2" >&2 ; fi

  # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
  RANK=($(cut -f2 ${TTAX} | awk -F"; " 'BEGIN{OFS="\t"}NR>1{for(i=1;i<=NF;i++){sub("__.*$", "", $i)};print }' | sort | uniq | tail -1))
  NRANK=${#RANK[@]}

  # ヘッダ行生成
  HDC=($(echo 'OTU_ID' 'Confidence' ${RANK[@]} 'Seq'))

  # taxonomyとASV配列をマージ
  # ランク毎のテーブルに整形、未分類のセルには空文字を入れる(そのままだとカラム数が揃わない)
  if [[ $NRANK == '7' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MSEQ
    paste <(tail +2 $TTAX | cut -f1,3) \
    <(tail +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
    <(cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') | awk -F"\t" '$1==$10' | cut -f1-9,11- >> $MSEQ

  elif [[ $NRANK == '8' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MSEQ
    paste <(tail +2 $TTAX | cut -f1,3) \
    <(tail +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}') \
    <(cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') | awk -F"\t" '$1==$11' | cut -f1-10,12- >> $MSEQ
  else 
    echo -e "[ERROR] The file format of inputs was invalid." >&2
  fi      

}

## 5.2.6. 関数定義: taxonomy rankごとに集計
function rankCnt () {
  # USAGE: taxcomp taxonomy_cnt.tsv outdir
  OTT=$1 ; OUTCNT=$2 
  if [[ ! -d ${OUTCNT} ]]; then echo "[ERROR] The ${OUTCNT} does not exists."; fi

  ## taxonomicランク列及びサンプル列を指定　
  ncol=`head -1 ${OTT} | awk -F"\t" '{print NF}'`
  ismp=10
  smps=(`head -1 ${OTT} | cut -f${ismp}-`)
  ntax=(`seq 3 $((${ismp}-1))`)
  nsmp=(`seq ${ismp} ${ncol}`)

  ## taxonomic rankの判定　silva, greengene, pr2で場合分け
  rank1=`head -1 ${OTT} | cut -f3`; rank2=`head -1 ${OTT} | cut -f4`
  if [[ $rank1 = 'd' && $rank2 = 'p' ]]; then
    rank=(domain phylum class order family genus species)
  elif [[ $rank1 = 'k' && $rank2 = 'p' ]]; then
    rank=(kingdom phylum class order family genus species)
  elif [[ $rank1 = 'd' && ! $rank2 = 'u' ]]; then
    rank=(domain supergroup phylum class order family genus species)
  fi

  ## 一時ディレクトリ作成
  TEMP=$(mktemp -d)
  trap 'rm -rf $TEMP' EXIT

  ## rank毎に行持ちデータフレームを作成し、要約
  for j in ${!ntax[@]}; do
    ptax=${ntax[$j]}; tax=${rank[$j]}
    for i in ${!nsmp[@]}; do
      psmp=${nsmp[$i]}; smp=${smps[$i]}
      cut -f${ptax},${psmp} ${OTT} | sed -e '1d' \
      | awk -F"\t" -v smp="${smp}" '{if($1==""){$1="Unassigned"}; arr[$1]+=$2}END{for(x in arr)print x"\t"smp"\t"arr[x]}'
    done > ${TEMP}/${tax}.cnt
  done

  ## 列持ちデータに変換
  abr=(`for i in ${rank[@]}; do echo ${i:0:1}; done`)
  for k in ${!rank[@]}; do 
    rnk=${rank[$k]}
    in=${TEMP}/${rnk}.cnt
    out=${OUTCNT}/count_${abr[$k]}.tsv

    for x in ${smps[@]}; do 
      cat ${in} | awk -F"\t" -v x=${x} '$2==x{print $1"\t"$3}' \
      | sort -t$'\t' -k1,1 > ${TEMP}/${rnk}_${x}.tmp
    done
  
    n_temp=`ls ${TEMP}/*.tmp | wc -l` # sample numbers
    slct=(`seq 2 2 $((${n_temp}*2))`) # column numbers of count data only
    echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
    paste ${TEMP}/${rnk}*.tmp | cut -f1,`echo ${slct[@]}|tr ' ' ','`  >> ${out}
  done

}

# 5.3. qzaファイル展開
## exported_txt内に展開される
unqza ${TAX} ${TAB} ${SEQ}

# 5.4. 出力ディレクトリ及び一時ディレクトリ作成
mkdir -p ${OUTD}
TEMP=$(mktemp -d)
trap "rm -rf ${TEMP}" EXIT

# 5.5. ラベル変更
RLIN1=exported_txt/feature-table.tsv; RLIN2=exported_txt/dna-sequences.fasta; RLIN3=exported_txt/taxonomy.tsv
RLOUT1=${TEMP}/relabel_cnt ;RLOUT2=${TEMP}/relabel_asv; RLOUT3=${TEMP}/relabel_tax 
relabel $RLIN1 $RLIN2 $RLIN3 $RLOUT1 $RLOUT2 $RLOUT3

# 5.6. フィルタリング
filterOtu $DP $RLOUT1 $RLOUT2 $RLOUT3 ${OTT} ${RTT} ${OTF} ${RTF} ${OTX} ${RTX}
if ls asv2otu.tsv > /dev/null ; then mv asv2otu.tsv ${OUTD}/. ; fi
echo "[INFO] Move asv2otu.tsv to ${OUTD} directory." >&2
# cat $OTT | wc -l 

# 5.7. フィルタ後のASV, feature-table, taxonomyをqzaに変換
## ASVをfastaに変換後qzaに変換
cat ${OTF} | awk -F"\t" 'NR>1{print ">" $1"\n"$2}' > ${OTFA}
qiime tools import --input-path ${OTFA} --output-path ${OTFAZ} --type 'FeatureData[Sequence]'

## taxonomy
qiime tools import --input-path ${OTX} --output-path ${OTXZ} --type 'FeatureData[Taxonomy]'

## feature-table をbiomに変換後qzaに変換
TMPBIOM=${TEMP}/tmp_biom
biom convert -i $OTT -o $TMPBIOM --to-hdf5
qiime tools import --input-path ${TMPBIOM} --output-path ${OTTZ} --type 'FeatureTable[Frequency]'

# 5.8. Merge taxonomy and feature-table
mtax $OTX $OTT $MTT

# 5.9. taxonomy rankごとに集計
rankCnt $MTT $OUTD

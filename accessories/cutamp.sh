#!/bin/bash
VERSION=0.0.240129
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### <CONTENTS> cutadaptを用いてアンプリコンリードの処理 ###
# 1. ドキュメント
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定
# 3. コマンドライン引数の処理
# 4. 引数の一覧
# 5. メインルーチン実行
#  5.1. 関数定義
#  5.2. cutadaptを実行
#  5.3. fastq-joinを実行
###

# 1. ドキュメント
function print_doc() {
cat << EOS
使用法:
  $CMDNAME [オプション] <read1.fastq.gz> <read2.fastq.gz>
  $CMDNAME [オプション] <fastq_dir>

説明:
  このプログラムはcutadaptを用いて、ペアエンドのアンプリコンリードからプライマー配列の除去を行います。
  入力ファイルとして、リード1とリード2のfastqファイルをコマンドライン引数として指定するか、
  fastqファイルを含むディレクトリを指定します。
  後者の場合、リード1およびリード2はファイル名中の[_R1|_R2]を識別します。

  primer配列を記述したファイルは、-pオプションで指定します[default: primers.txt]。
  primerファイルの書式は以下のような、スペースまたはタブ区切りのテキストファイルです。
  [v3v4  FORWRDPRIMER  REVERSEPRIMER]

オプション:
  -p    プライマーファイル[default: primers.txt]
  -r    リージョン選択 [e.g. : v3v4]
  -s    fastqファイルのサフィックス[default: fastq.gz]
  -j    fastq-joinを用いてペアエンド結合を実施
  -o    cutadaptの出力ディレクトリ
  -O    fastq-joinの出力ディレクトリ

  cutadaptのオプション
  -d    アダプター配列未除去の配列は捨てる
  -q    アダプター除去の前に、各リードの5'末端および3'末端から低品質塩基をトリミング[default: 20]
  -c    CPU [default: 6]
  -h    ヘルプドキュメントの表示

  fastq-joinのオプション
  -N    最大ミスマッチパーセント[default:8]
  -t    joinした後でこの値より短い配列は除去 [default:0]


使用例:
  # fastqのディレクトリ指定(primer.txtのパスを通しておけば-pは省略可)
  $CMDNAME -p primers.txt -r v3v4 ./fastq_dir
  $CMDNAME -r v3v4 ./fastq_dir

  # リード1とリード2を指定(fastqファイルのサフィックスは-sオプションで変更可)
  $CMDNAME -r v3v4 read1.fastq.gz read2.fastq.gz
  $CMDNAME -r v3v4 -s fq.gz read1.fq.gz read2.fq.gz

  # ペアエンド結合
  $CMDNAME -j -r v3v4 ./fastq_dir

  # フルオプション指定
  cutamp.sh -p primers.txt -r v3v4 -s fastq.gz -o cutfq -O jnfq -j -q 20 -d -N 16 -t 100 -c 16 ./fastq 2> cutamp.log

EOS
}
if [[ $# = 0 ]]; then print_doc; exit 1; fi

# 2. Check arguments
## 2.1. オプション引数の入力
while getopts p:r:s:o:O:dq:jN:t:c:h OPT
do
  case $OPT in
    "p" ) PRM="$OPTARG" ;;
    "r" ) REGION="$OPTARG" ;;
    "s" ) SFX="$OPTARG";;
    "o" ) OUT="$OPTARG" ;;
    "O" ) OUTJN="$OPTARG" ;;
    "d" ) FLG_d="TRUE" ;;
    "q" ) QV="$OPTARG" ;;
    "j" ) FLG_j="TRUE" ;;
    "N" ) NP="$OPTARG" ;;
    "t" ) TRNK="$OPTARG" ;;
    "c" ) NT="$OPTARG" ;;
    "h" ) print_doc ; exit 1 ;; 
     \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

## 2.2. オプション引数のチェック及びデフォルト値の指定
if [[ -z "$PRM" ]]; then PRM="$(dirname $0)/primers.txt" ; fi
if [[ ! -f "$PRM" ]]; then echo "[ERROR] '$PRM' does not exist." ; exit 1; fi
if [[ -z "$REGION" ]]; then echo "[ERROR] Region name must be set with '-r' option." ; exit 1; fi
FP=$(cat ${PRM} | awk -F"[\x20\t]+" -v REGION="${REGION}" '$1==REGION{print $2}')
RP=$(cat ${PRM} | awk -F"[\x20\t]+" -v REGION="${REGION}" '$1==REGION{print $3}')
if [[ $FP == "" || $RP == "" ]]; then echo "[ERROR] You should select as follows."; cat ${PRM}; echo; exit 1 ;fi
if [[ -z "$SFX" ]]; then SFX='fastq.gz'; fi
if [[ "$FLG_d" != 'TRUE' ]]; then FLG_d='FALSE'; fi
if [[ -z "$QV" ]]; then QV='20'; fi
if [[ -z "$OUT" ]]; then OUT='cutfq' ; fi
if [[ -d "$OUT" ]]; then echo -e "[ERROR] The ${OUT} was already exists." >&2 ; exit 1; fi
if [[ -z "$NT" ]]; then NT=6 ; fi
if [[ "$FLG_j" = 'TRUE' ]]; then 
  if [[ -z "$NP" ]]; then NP='8' ;  fi
  if [[ -z "$TRNK" ]]; then TRNK='100' ;  fi
  if [[ -z "$OUTJN" ]]; then OUTJN='jnfq' ;  fi
  if [[ -d "$OUTJN" ]]; then echo -e "[ERROR] The ${OUTJN} was already exists." >&2 ; exit 1; fi
else
  unset NP TRNK OUTJN
fi
LOG=$(date +"%Y%m%dT%H%M")_cutamp.log
LOGJN=$(date +"%Y%m%dT%H%M")_join.log

## 2.3. Command line arguments
if [[ $# = 2 && -f "$1" && -f "$2" && "$1" != "$2" ]]; then
  R1=$1 ; R2=$2
elif [[ $# = 1 && -d "$1" ]]; then
  FQD=$1
  ls ${FQD}/*.${SFX} > /dev/null 2>&1 || { echo "[ERROR] ${FQD} does not containg fastq files[ .${SFX} ]." >&2 ; exit 1; }
  for r1 in $(ls ${FQD}/*.${SFX} | grep "_R1"); do
    r2=${r1/_R1/_R2} 
    if [[ ${r1} == "" || ${r2} == "" ]] ; then echo "[ERROR] Read1, Read2, or both missing." >&2 ; exit 1 ; fi
  done
else
  echo "[ERROR] fastqファイルがみつかりません" >&2 ; exit 1
fi

## 3. Check requirements
if ! command -v cutadapt &> /dev/null; then echo "[ERROR] Could not find cutadapt" >&2 ; exit 1; fi
if ! command -v fastq-join &> /dev/null; then echo "[ERROR] Could not find fastq-join" >&2 ; exit 1; fi

# 4. Print arguments
cat << EOS | tee -a ${LOG} >&2
### Arguments ###
Primer file                     [ ${PRM} ]
Region name                     [ ${REGION} ]
Forward primer                  [ ${FP} ]
Reverse primer                  [ ${RP} ]
Read1                           [ ${R1} ]
Read2                           [ ${R2} ]
Input directory                 [ ${FQD} ]

Output cutadapted fastq         [ ${OUT} ]
Discard reads with no adapter   [ ${FLG_d} ]
Quality trimming on both ends   [ ${QV} ]

Paired end merge                [ ${FLG_j} ]
Output merged fastq             [ ${OUTJN}]
Maximum mismatch percent        [ ${NP} ]
Discard joined reads length     [ ${TRNK} ]

The number of threads           [ ${NT} ]

EOS

# 5. Main
## 5.1. Functions 
function cutamp (){
  # usage: cutamp <read1.fq.gz> <read2.fq.gz> <f_primer> <r_primer_> <out_dir> <TRUE> <12> <20>
  # usage: cutamp ../fastq/C1_S244_L001_R1_001.fastq.gz ../fastq/C1_S244_L001_R2_001.fastq.gz CCTACGGGNBGCASCAG GACTACNNGGGTATCTAATCC cutfq TRUE 12 20
  unset PFX RP1RC FP1RC CUTLOG R1CUT R2CUT OPTD
  local R1=$1 ; local R2=$2 ; local FP1=$3 ; local RP1=$4 ; local OUT=$5 ; local FLGD=$6 ; local THRD=$7 ; local QV=$8 ; 
  function revcomp(){ echo $1 | tr ATGCYRKMWBVDHNatgcyrkmwbvdhn TACGRYMKWVBHDNtacgrymkwvbhdn | rev ; }

  # Arguments
  local PFX=$(basename $R1 | cut -f1 -d"_")
  local RP1RC=$(revcomp ${RP1}); local FP1RC=$(revcomp ${FP1})
  local CUTLOG=${OUT}/${PFX}_cut.log 
  local R1CUT=${OUT}/${PFX}_cut_R1.fastq.gz ; local R2CUT=${OUT}/${PFX}_cut_R2.fastq.gz

  if [[ ${FLGD} == 'TRUE' ]] ; then OPTD='--discard-untrimmed' ; fi
  if [[ ! -d ${OUT} ]] ; then echo "[ERROR] The output directory dones not exist" ; return 1 ; fi
  ## echo -e $PFX"\t"$RP1RC"\t"$FP1RC"\t"$CUTLOG"\t"$FLGD"\t"$OPTD"\t"$OUT 
  
  # Run cutadapt
  cmd="cutadapt ${OPTD} -j ${THRD} -q ${QV},${QV} -m 1 -n 2 -g ${FP1} -a ${RP1RC} -G ${RP1} -A ${FP1RC} -o ${R1CUT} -p ${R2CUT} ${R1} ${R2} > ${CUTLOG}" 
  echo ${cmd} >&2 ; eval ${cmd}
}

function joinampz () {
  unset PFX JNFQ
  # usage: joinampz cutqt_1.fq.gz cutqt_2.fq.gz 8 100 ./jnfq
  local R1=$1 ; local R2=$2 ; local NP=$3 ; local LEN=$4 ; local JNOUT=$5
  local PFX=$(basename $R1 | cut -f1 -d"_")
  local JNLOG="${JNOUT}/${PFX}_join.log"

  # Run fastq join
  PFX=$(basename $R1 | cut -f1 -d"_")
  echo ">${PFX}" > ${JNLOG}
  cmd="fastq-join -p ${NP} <(gunzip -c ${R1}) <(gunzip -c ${R2}) -o ${JNOUT}/${PFX}_%.fastq "
  echo ${cmd} >&2 ; eval ${cmd} >> ${JNLOG}

}

function fqFltLen () { 
    local FQ=$1; local LEN=$2 
    cat ${FQ} | awk '{ printf("%s",$0); n++; if(n%4==0) { printf("\n");} else { printf("\t");} }' \
    | awk -F"\t" -v LEN=${LEN} '{if(length($2)>LEN)printf("%s", $1"\n"$2"\n"$3"\n"$4"\n");}' 
}

function fqHistLen () { 
  awk '(NR - 1) % 4 == 1 { print length($0) }' $1 | sort | uniq -c | sort -n -k2,2 
}
function fqPer () {
  FQ=$1
  CNT=$((`cat $FQ |wc -l`/4))
  P10=$(($CNT*10/100)); P30=$(($CNT*30/100)); P50=$(($CNT*50/100)); P70=$(($CNT*70/100)); P90=$(($CNT*90/100)); 
  Per10=$(fqHistLen $FQ | sed -e "s/^ *//" | awk -v p10=$P10 '{cumsum+=$1; if(cumsum > p10){print $2; exit;}}')
  Per30=$(fqHistLen $FQ | sed -e "s/^ *//" | awk -v p30=$P30 '{cumsum+=$1; if(cumsum > p30){print $2; exit;}}')
  Per50=$(fqHistLen $FQ | sed -e "s/^ *//" | awk -v p50=$P50 '{cumsum+=$1; if(cumsum > p50){print $2; exit;}}')
  Per70=$(fqHistLen $FQ | sed -e "s/^ *//" | awk -v p70=$P70 '{cumsum+=$1; if(cumsum > p70){print $2; exit;}}')
  Per90=$(fqHistLen $FQ | sed -e "s/^ *//" | awk -v p90=$P90 '{cumsum+=$1; if(cumsum > p90){print $2; exit;}}')
  echo -e $Per10";"$Per30";"$Per50";"$Per70";"$Per90
}
function fqzCnt () { 
  ID=$(basename $1 | cut -f1 -d"_"); echo -e "${ID}\t$(($(gunzip -c $1 | wc -l)/4))"; 
}
# function cut_log () {}

function join_log () {
  local JNLOG=$1
  cat ${JNLOG} | awk -F'\t' '{ \
  if($1~/^>/){sub(">","",$1); printf $1"\t";} \
  else if($1~/Total reads:/){sub("Total reads: ","",$1); printf $1"\t";} \
  else if($1~/Total joined:/){sub("Total joined: ","",$1);printf $1"\t"} \
  else if($1~/Average join len:/){sub("Average join len: ","",$1);printf $1"\t" } \
  else if($1~/Stdev join len:/){sub("Stdev join len: ","",$1);printf $1"\t" } \
  else if($1~/Version:/){sub("Version: ","",$1);print $1 }}'

}


## 5.2. Main routine
### Cutadapt
mkdir -p ${OUT}
if [[ ! ${FQD} = "" ]]; then 
  for r1 in $(ls ${FQD}/*.${SFX} | grep "_R1"); do
   r2=${r1/_R1/_R2} 
   if [[ ${r1} == "" || ${r2} == "" ]] ; then echo "[ERROR] Read1, Read2, or both missing." >&2 ; exit 1 ; fi
   #echo -e $r1"\t"$r2"\t"$FP"\t"$RP"\t"$OUT"\t"$FLG_d"\t"$NT"\t"$QV
   cutamp ${r1} ${r2} ${FP} ${RP} ${OUT} ${FLG_d} ${NT} ${QV} | tee -a ${LOG} >&2
  done
else 
  #echo -e $R1"\t"$R2"\t"$FP"\t"$RP"\t"$OUT"\t"$FLG_d"\t"$NT"\t"$QV
  cutamp $R1 $R2 $FP $RP $OUT $FLG_d $NT $QV 
fi
# Parse cutadapt log

### fastq-join
if [[ ${FLG_j} = 'TRUE' ]]; then
  mkdir -p ${OUTJN}
  for r1 in $(ls ${OUT}/*_R1.fastq.gz) ; do 
    PFX=$(basename $r1 | cut -f1 -d"_")
    r2=${r1/_R1/_R2}
    joinampz ${r1} ${r2} ${NP} ${TRNK} ${OUTJN} | tee -a ${LOG} >&2

  done 

  # Fastq filtering with read length and compressed 
  JNFQ=${OUTJN}/${PFX}_join.fastq
  for i in ${OUTJN}/*_join.fastq; do 
   PFX=$(basename $i | cut -f1 -d"_")
   fqFltLen ${i} ${TRNK} | gzip > ${i}.gz
  done

  ## Stats of joined fastq # Parse fastq-join log
  paste <(cat ${OUTJN}/*.log | join_log) \
  <(for i in ${OUTJN}/*_join.fastq; do fqPer $i; done ) \
  <(for i in ${OUTJN}/*_join.fastq.gz; do echo $(($(gunzip -c $i | wc -l)/4)) ; done ) > ${LOGJN}

  # Remove trash
  rm ${OUTJN}/*.fastq
fi

exit 0

#!/usr/bin/env nextflow

nextflow.preview.dsl=2
include GenomeGenerate from './NextflowModules/STAR/2.6.0c/GenomeGenerate.nf' params(params)
include Index as SalmonIndex from './NextflowModules/Salmon/0.13.1/Index.nf' params( optional:params.salmonindex.toolOptions )
include GtfToGenePred from './NextflowModules/ucsc/377/gtfToGenePred/GtfToGenePred.nf' params(params)
include GenePredToBed from './NextflowModules/ucsc/377/genePredToBed/GenePredToBed.nf' params(params)
include CreateSequenceDictionary from './NextflowModules/Picard/2.22.0/CreateSequenceDictionary.nf' params(params)
include CreateIntervalList from './NextflowModules/Utils/CreateIntervaList.nf' params(params)
include getExonLenghts from './utils/getExonLengths.nf' params(params)
include './NextflowModules/Utils/fastq.nf' params(params)
include post_mapping_QC from './sub-workflows/post_mapping_QC.nf' params(params)
include markdup_mapping from './sub-workflows/mapping_deduplication.nf' params(params)
include multiqc_report from './sub-workflows/multiqc_report.nf' params(params)
include SplitIntervals from './NextflowModules/GATK/4.1.3.0/SplitIntervals.nf' params(optional: params.splitintervals.toolOptions)
include gatk4_bqsr from './sub-workflows/gatk4_bqsr.nf' params(params)
include gatk4_hc from './sub-workflows/gatk4_hc.nf' params(params)
include SplitNCigarReads from './NextflowModules/GATK/4.1.3.0/SplitNCigarReads.nf' params(genome_fasta:params.genome_fasta)
include Count from './NextflowModules/HTSeq/0.11.3/Count.nf' params(hts_count_type:params.hts_count_type, 
								    optional:params.count.toolOptions, 
								    singleEnd:params.singleEnd, 
								    stranded:params.stranded, 
								    unstranded:params.unstranded, 
								    revstranded:params.revstranded)
include AlignReads from './NextflowModules/STAR/2.6.0c/AlignReads.nf' params(singleEnd:params.singleEnd, 
									     optional:params.star.toolOptions)
include Index from './NextflowModules/Sambamba/0.6.8/Index.nf' params(params)
include gatk4_rnaseq from './sub-workflows/gatk4_rnaseq.nf' params(params)
include Quant from './NextflowModules/Salmon/0.13.1/Quant.nf' params(singleEnd: params.singleEnd,
                                                                     stranded: params.stranded,
                                                                     unstranded: params.unstranded,
                                                                     revstranded: params.revstranded,
                                                                     saveUnaligned: params.saveUnaligned)
include Fastp from './NextflowModules/fastp/0.14.1/Fastp.nf' params(optional:params.fastp.toolOptions, 
								    singleEnd:params.singleEnd )
include mergeFastqLanes from './NextflowModules/Utils/mergeFastqLanes.nf' params(params)
include mergeHtseqCounts from './utils/mergeHtseqCounts.nf' params(params)
include rpkm from './utils/bioconductor/edger/3.28.0/rpkm.nf' params(params)
include FeatureCounts from './NextflowModules/subread/2.0.0/FeatureCounts.nf' params(optional:params.fc.toolOptions,
										     extraAttributes:params.fc.extraAttributes,
										     stranded:params.stranded,
                                                                                     unstranded:params.unstranded,
                                                                                     revstranded:params.revstranded,
										     fc_group_features:params.fc_group_features,
										     fc_count_type:params.fc_count_type)
if (!params.out_dir) {
   exit 1, "Output directory not found. Please provide the correct path!"
}

workflow {
  main :  
    run_name = params.fastq_path.split('/')[-1]
    fastq_files = extractAllFastqFromDir(params.fastq_path)
    //Get necessary files
    genome_gtf = Channel
        .fromPath(params.genome_gtf, checkIfExists: true)
        .ifEmpty { exit 1, "GTF file not found: ${params.genome_gtf}"}
    genome_fasta = Channel
        .fromPath(params.genome_fasta, checkIfExists: true)
        .ifEmpty { exit 1, "Fasta file not found: ${params.genome_fasta}"}
    genome_index = Channel
        .fromPath(params.genome_fasta + '.fai', checkIfExists: true)
        .ifEmpty { exit 1, "Fai file not found: ${params.genome_fasta}.fai"}

    if (params.gene_len && !params.skipCount && !params.skipMapping) {
      exon_lengths = params.gene_len
    } else if (!params.gene_len && !params.skipCount && !params.skipMapping) {
      getExonLenghts( genome_gtf)
      exon_lengths = getExonLenghts.out
    } 

    if (params.star_index && !params.skipMapping) {
      star_index = Channel
            .fromPath(params.star_index, checkIfExists: true)
            .ifEmpty { exit 1, "STAR index not found: ${params.star_index}"}
    } else if (!params.star_index && !params.skipMapping) {
      //Create STAR Index
      GenomeGenerate ( genome_fasta, genome_gtf )
      star_index = GenomeGenerate.out
    }
    if (params.genome_bed && !params.skipPostQC && !params.skipMapping) {
      //Create bed12 index file
      genome_bed = Channel
            .fromPath(params.genome_bed, checkIfExists: true)
            .ifEmpty { exit 1, "Bed12 file not found: ${params.genome_bed}"}
    } else if ( !params.genome_bed && !params.skipPostQC && !params.skipMapping) {
        GtfToGenePred ( genome_gtf)
        GenePredToBed ( GtfToGenePred.out )
        genome_bed = GenePredToBed.out
    }
    if ( params.salmon_index && !params.skipSalmon) {
       salmon_index = Channel
            .fromPath(params.salmon_index, checkIfExists: true)
            .ifEmpty { exit 1, "Transcripts fasta not found: ${params.salmon_index}"}
    } else if ( !params.salmon_index && !params.skipSalmon ) {
        transcripts_fasta = Channel
            .fromPath(params.transcripts_fasta, checkIfExists: true)
            .ifEmpty { exit 1, "Fasta file not found: ${params.transcripts_fasta}"}
      SalmonIndex ( transcripts_fasta )
      salmon_index = SalmonIndex.out
    }
    if (params.scatter_interval_list && !params.skipGATK4_HC ) {
      scatter_interval_list = Channel
        .fromPath( params.scatter_interval_list, checkIfExists: true)
        .ifEmpty { exit 1, "Scatter intervals not found: ${params.scatter_interval_list}"}
    } else if ( !params.scatter_interval_list && !params.skipGATK4_HC) {
        CreateSequenceDictionary (genome_fasta)
        CreateIntervalList(genome_index, CreateSequenceDictionary.out )
        scatter_interval_list = CreateIntervalList.out
    }
   
    if (params.singleEnd) {
      if (!params.skipFastp) {
        final_fastqs = Fastp(fastq_files)
              .groupTuple(by:0)
              .map { sample_id, rg_ids, json, reads -> [sample_id, rg_ids[0], reads.toSorted(), [], json] }
              
      } else {
          final_fastqs = fastq_files
          .groupTuple(by:0)
          .map { sample_id, rg_ids, reads -> [sample_id, rg_ids[0], reads.flatten().toSorted(), [], []] }
          }
    } else {
          if (!params.skipFastp) {
            final_fastqs =  Fastp(fastq_files)
              .map{ sample_id, rg_ids, json, reads -> [sample_id, rg_ids, reads[0], reads[1], json] }
              .groupTuple(by:0)
              .map{ sample_id, rg_ids, r1, r2, json -> [sample_id, rg_ids[0], r1.toSorted(), r2.toSorted(), json] }
          } else {
            final_fastqs = fastq_files
              .map{ sample_id, rg_ids, reads -> [sample_id, rg_ids, reads[0], reads[1]] }
              .groupTuple(by:0)
              .map{ sample_id, rg_ids, r1, r2 -> [sample_id, rg_ids[0], r1.toSorted(), r2.toSorted(), []] }
          }
    }

    if (!params.skipMapping) {
      AlignReads(final_fastqs.map { sample_id, rg_id, r1, r2, json -> [sample_id, rg_id, r1, r2] }, star_index.collect())
      Index(AlignReads.out.map { sample_id, bams, unmapped, log1, log2, tab -> [sample_id, bams] })
      mapped = AlignReads.out.join(Index.out)
    }
    if (!params.skipPostQC && !params.skipMapping) {
      post_mapping_QC(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, bams, bai] }, genome_bed.collect())
    }
    if (!params.skipCount && !params.skipMapping) {
      FeatureCounts(run_name, AlignReads.out.map { it[1] }.collect(), genome_gtf.collect()) 
      Count(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, bams, bai] }, genome_gtf.collect())
      mergeHtseqCounts( run_name, Count.out.map { it[1] }.collect())
      rpkm( run_name, mergeHtseqCounts.out, exon_lengths)
    }
    if (!params.skipMarkDup && !params.skipMapping) {
      markdup_mapping(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, sample_id, bams, bai] })
    }
    if (!params.skipSalmon) {
      Quant ( mergeFastqLanes (final_fastqs.map { sample_id, rg_id, r1, r2, json -> [sample_id, rg_id, r1, r2] }), salmon_index.collect())
    }
    if (!params.skipMapping && !params.skipMarkDup && !params.skipGATK4_HC) {
          SplitIntervals( 'no-break', scatter_interval_list)
          SplitNCigarReads(markdup_mapping.out)
          if (!params.skipGATK4_BQSR) {
            //Perform BSQR
            gatk4_bqsr(SplitNCigarReads.out, SplitIntervals.out.flatten())
            gatk4_hc(gatk4_bqsr.out[0], SplitIntervals.out.flatten())
          } else {
              gatk4_hc(SplitNCigarReads.out, SplitIntervals.out.flatten())
          }      
    }
    if (!params.skipMultiQC) {
      multiqc_report( final_fastqs.map { it[-1] }, 
		      AlignReads.out.map{ [it[3], it[4]] }, 
                      post_mapping_QC.out[1].map { it[1] }.mix(post_mapping_QC.out[0].map { it[1] }),  
                      Count.out.map { it[1] } )
   }

}

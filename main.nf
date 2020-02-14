#!/usr/bin/env nextflow

nextflow.preview.dsl=2

include './NextflowModules/Utils/fastq.nf' params(params)
include FastQC from './NextflowModules/FastQC/0.11.5/FastQC.nf' params(params)
include TrimGalore from './NextflowModules/TrimGalore/0.6.1/TrimGalore.nf' params(params)
include star_mapping from './sub-workflows/star_mapping.nf' params(params) 
include post_mapping_QC from './sub-workflows/post_mapping_QC.nf' params(params)
include markdup_mapping from './sub-workflows/mapping_deduplication.nf' params(params)
include Count from './NextflowModules/HTSeq/0.6.0/Count.nf' params(params)

workflow {
  main :
    genome_index = Channel.fromPath(params.star_index)
    genome_bed = Channel.fromPath(params.genome_bed)
    genome_model = Channel.fromPath(params.genome_gtf)
    fastq_files = extractFastqFromDir(params.fastq_path)
    if (!params.skipFastQC) {
        FastQC(fastq_files) 
    }
    if (params.singleEnd) {
        if (!params.skipTrimming) {
	    trimmed = TrimGalore(fastq_files)
	    final_fastqs = trimmed.groupTuple(by:0).map { sample_id, rg_ids, reads, logs, fqc -> [sample_id, rg_ids[0], reads.toSorted(), []]}
 	} else {
            final_fastqs = fastq_files.groupTuple(by:0).map { sample_id, rg_ids, reads -> [sample_id, rg_ids[0], reads.flatten().toSorted(), []]}
        }          
    } else {
        if (!params.skipTrimming) {
            trimmed = TrimGalore(fastq_files)
            final_fastqs = trimmed.map{ sample_id, rg_ids, reads, fqc, logs -> [sample_id, rg_ids, reads[0], reads[1]] }.groupTuple(by:0).map{ sample_id, rg_ids, r1, r2 -> [sample_id, rg_ids[0], r1.toSorted(), r2.toSorted()] }
        } else {
            final_fastqs = fastq_files.map{ sample_id, rg_ids, reads -> [sample_id, rg_ids, reads[0], reads[1]] }.groupTuple(by:0).map{ sample_id, rg_ids, r1, r2 -> [sample_id, rg_ids[0], r1.toSorted(), r2.toSorted()] }
        }
    } 
    if (!params.skipMapping) {
    	star_mapped = star_mapping(final_fastqs, genome_index.collect())
    	mapped = star_mapped.bams.join(star_mapped.bais)
    }
    if (!params.skipPostQC && !params.skipMapping) {
    	post_mapping_QC(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, bams, bai] },genome_bed.collect())
    }
    if (!params.skipCount && !params.skipMapping) {
	Count(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, bams, bai] },genome_model.collect())
    }
    if (!params.skipMarkDup && !params.skipMapping) {
    	markdup_mapping(mapped.map { sample_id, bams, unmapped, log1, log2, tab, bai -> [sample_id, sample_id,  bams, bai] })
    }
}

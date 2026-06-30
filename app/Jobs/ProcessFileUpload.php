<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Models\File;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;

class ProcessFileUpload implements ShouldQueue
{
    use Queueable;

    public function __construct(public File $file) {}

    public function handle(): void
    {
        Log::info('ProcessFileUpload', [
            'file_id' => $this->file->id,
            'worker_hostname' => gethostname(),
            'processed_at' => now()->toIso8601String(),
        ]);
    }
}

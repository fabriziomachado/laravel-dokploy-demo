<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\WithFaker;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use App\Models\File;

class FileUploadTest extends TestCase
{
    use RefreshDatabase;

    public function test_files_page_is_accessible()
    {
        $response = $this->get('/files');

        $response->assertStatus(200);
        $response->assertSee('Uploaded Files');
    }

    public function test_file_can_be_uploaded()
    {
        Storage::fake('local');

        $file = UploadedFile::fake()->create('document.pdf', 100);

        $response = $this->post('/files', [
            'file' => $file,
        ]);

        $response->assertRedirect('/files');

        // Assert the file was stored...
        Storage::disk('local')->assertExists('uploads/' . $file->hashName());

        // Assert the file was recorded in the database...
        $this->assertDatabaseHas('files', [
            'original_name' => 'document.pdf',
        ]);
    }

    public function test_file_can_be_deleted()
    {
        Storage::fake('local');

        $file = UploadedFile::fake()->create('document.pdf', 100);
        // Upload first to get the path and DB record
        $path = $file->store('uploads', 'local');

        $fileRecord = File::create([
            'original_name' => 'document.pdf',
            'path' => $path,
        ]);

        $response = $this->delete("/files/{$fileRecord->id}");

        $response->assertRedirect('/files');

        // Assert the file was deleted from storage...
        Storage::disk('local')->assertMissing($path);

        // Assert the file was deleted from database...
        $this->assertDatabaseMissing('files', [
            'id' => $fileRecord->id,
        ]);
    }
}

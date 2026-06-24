<?php

namespace App\Http\Controllers;

use App\Models\File;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class FileController extends Controller
{
    public function index()
    {
        $files = File::latest()->get();
        $containerId = gethostname();
        return view('files.index', compact('files', 'containerId'));
    }

    public function create()
    {
        return view('files.create');
    }

    public function store(Request $request)
    {
        $request->validate([
            'file' => 'required|file|max:10240', // 10MB max
        ]);

        // {{ ... }} // This line was causing a syntax error and has been commented out.

        $uploadedFile = $request->file('file');
        $originalName = $uploadedFile->getClientOriginalName();
        $path = $uploadedFile->store('uploads'); // Stored in storage/app/uploads (typically private)
// If we want it public we should use 'public/uploads' but the prompt says simple system, private is fine for now unless
// download is via public link.
// Let's use storage path and a download route to keep it secure/managed.

        File::create([
            'original_name' => $originalName,
            'path' => $path,
        ]);

        return redirect()->route('files.index')->with('success', 'File uploaded successfully.');
    }

    public function destroy(File $file)
    {
        Storage::delete($file->path);
        $file->delete();

        return redirect()->route('files.index')->with('success', 'File deleted successfully.');
    }

    public function download(File $file)
    {
        return Storage::download($file->path, $file->original_name);
    }
}
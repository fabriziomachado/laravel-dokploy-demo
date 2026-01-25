<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return redirect()->route('files.index');
});

Route::resource('files', \App\Http\Controllers\FileController::class)->except(['edit', 'update', 'show']);
Route::get('files/{file}/download', [\App\Http\Controllers\FileController::class, 'download'])->name('files.download');

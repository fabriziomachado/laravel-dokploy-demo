@extends('layouts.app')

@section('content')
    <div class="mb-6">
        <a href="{{ route('files.index') }}" class="text-blue-500 hover:text-blue-800">&larr; Back to List</a>
    </div>

    <div class="w-full max-w-lg mx-auto bg-white shadow-md rounded px-8 pt-6 pb-8 mb-4">
        <h2 class="text-2xl font-bold mb-6 text-gray-800">Upload File</h2>

        <form action="{{ route('files.store') }}" method="POST" enctype="multipart/form-data">
            @csrf

            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2" for="file">
                    Choose File
                </label>
                <input
                    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline @error('file') border-red-500 @enderror"
                    id="file" type="file" name="file">
                @error('file')
                    <p class="text-red-500 text-xs italic mt-2">{{ $message }}</p>
                @enderror
            </div>

            <div class="flex items-center justify-between">
                <button
                    class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
                    type="submit">
                    Upload
                </button>
            </div>
        </form>
    </div>
@endsection
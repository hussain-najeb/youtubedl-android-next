package org.foss.youtube.next

class YoutubeDLRequest {
    private val urls: List<String>
    private val options = YoutubeDLOptions()
    private val customCommandList: MutableList<String> = ArrayList()

    constructor(url: String) {
        urls = listOf(url)
    }

    constructor(urls: List<String>) {
        this.urls = urls
    }

    fun addOption(option: String, argument: String): YoutubeDLRequest {
        options.addOption(option, argument)
        return this
    }

    fun addOption(option: String, argument: Number): YoutubeDLRequest {
        options.addOption(option, argument)
        return this
    }

    fun addOption(option: String): YoutubeDLRequest {
        options.addOption(option)
        return this
    }

    fun addCommands(commands: List<String>): YoutubeDLRequest {
        customCommandList.addAll(commands)
        return this
    }

    fun getOption(option: String): String? = options.getArgument(option)

    fun getArguments(option: String): List<String?>? = options.getArguments(option)

    fun hasOption(option: String): Boolean = options.hasOption(option)

    fun buildCommand(): List<String> {
        val commandList: MutableList<String> = ArrayList()
        commandList.addAll(options.buildOptions())
        commandList.addAll(customCommandList)
        commandList.addAll(urls)
        return commandList
    }
}
